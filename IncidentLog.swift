//
//  IncidentLog.swift
//  MercyDrones — Alerts & log
//
//  Every pin placed or deleted and every boundary drawn or deleted on the map
//  is written here (MapAnnotationStore does the recording), and the Alerts tab
//  shows it newest first. The log is kept on the device for now (a JSON file
//  in Documents) and handed to an `IncidentLogSync`, which does nothing until
//  a backend is plugged in.
//

import Foundation

// MARK: - Entries

struct LogEntry: Identifiable, Codable, Equatable {
    // Raw values are the sync wire format, so don't rename them.
    enum Kind: String, Codable {
        case pinPlaced = "pin_placed"
        case pinRemoved = "pin_removed"
        case boundaryDrawn = "boundary_drawn"
        case boundaryRemoved = "boundary_removed"
    }

    var id = UUID()
    var kind: Kind
    var title: String
    var detail: String
    /// Set for pin entries, so the log can show the pin's logo.
    var pinCategory: PinCategory?
    /// Set for boundary entries: the cover color as 0xRRGGBB.
    var colorHex: UInt32?
    var coordinate: GeoPoint?
    var urgent = false
    /// The device that logged it. Entries synced in from other teams keep theirs.
    var deviceID = ResponderDevice.id
    var createdAt = Date()

    var isMine: Bool { deviceID == ResponderDevice.id }
}

extension LogEntry {
    static func pinPlaced(_ pin: HazardPin) -> LogEntry {
        LogEntry(kind: .pinPlaced,
                 title: "Pin placed · \(pin.title)",
                 detail: coordinateText(pin.coordinate),
                 pinCategory: pin.category,
                 coordinate: pin.coordinate,
                 urgent: pin.category.isUrgent)
    }

    static func pinRemoved(_ pin: HazardPin) -> LogEntry {
        LogEntry(kind: .pinRemoved,
                 title: "Pin removed · \(pin.title)",
                 detail: coordinateText(pin.coordinate),
                 pinCategory: pin.category,
                 coordinate: pin.coordinate)
    }

    static func boundaryDrawn(_ boundary: IncidentBoundary) -> LogEntry {
        LogEntry(kind: .boundaryDrawn,
                 title: "Boundary drawn · \(boundary.name)",
                 detail: "\(boundary.points.count) corners · \(BoundaryCover.name(for: boundary.colorHex).lowercased()) cover",
                 colorHex: boundary.colorHex,
                 coordinate: boundary.points.first)
    }

    static func boundaryRemoved(_ boundary: IncidentBoundary) -> LogEntry {
        LogEntry(kind: .boundaryRemoved,
                 title: "Boundary removed · \(boundary.name)",
                 detail: "\(boundary.points.count) corners",
                 colorHex: boundary.colorHex,
                 coordinate: boundary.points.first)
    }

    private static func coordinateText(_ point: GeoPoint) -> String {
        String(format: "%.4f, %.4f", point.latitude, point.longitude)
    }
}

/// Identifies this install, so the log can tell your entries from other teams'.
enum ResponderDevice {
    static let id: String = {
        let key = "responderDeviceID"
        if let saved = UserDefaults.standard.string(forKey: key) { return saved }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: key)
        return new
    }()
}

// MARK: - Sync

/// Hook for sharing Alerts & log with every team on the incident.
///
/// The log only ever grows, so syncing is a merge, never an overwrite: `push`
/// sends each entry recorded on this device (entries that fail are retried on
/// the next refresh), and `pull` returns entries from every team. Any the
/// device hasn't seen are added by `id`. To sync, write a type that talks to
/// the backend and pass it as `IncidentLog(sync:)` in `MercyDronesApp`.
protocol IncidentLogSync: Sendable {
    func push(_ entry: LogEntry) async throws
    func pull() async throws -> [LogEntry]
}

/// The default: nothing leaves the device.
struct LocalOnlyLogSync: IncidentLogSync {
    func push(_ entry: LogEntry) async throws {}
    func pull() async throws -> [LogEntry] { [] }
}

// MARK: - Store

final class IncidentLog: ObservableObject {
    /// Newest first.
    @Published private(set) var entries: [LogEntry]

    private let fileURL: URL?
    private let sync: IncidentLogSync
    /// Entries recorded here that the backend hasn't accepted yet.
    private var unsent: Set<UUID>

    /// Pass `fileURL: nil` to keep everything in memory (previews).
    init(fileURL: URL? = URL.documentsDirectory.appending(path: "incident-log.json"),
         sync: IncidentLogSync = LocalOnlyLogSync()) {
        self.fileURL = fileURL
        self.sync = sync
        let saved = Self.load(from: fileURL)
        entries = saved?.entries ?? []
        unsent = saved?.unsent ?? []
    }

    func record(_ entry: LogEntry) {
        entries.insert(entry, at: 0)
        unsent.insert(entry.id)
        save()
        Task { await send([entry]) }
    }

    /// Retries anything unsent, then merges in every team's entries.
    @MainActor
    func refresh() async {
        await send(entries.filter { unsent.contains($0.id) })
        guard let remote = try? await sync.pull() else { return }
        let known = Set(entries.map(\.id))
        let new = remote.filter { !known.contains($0.id) }
        guard !new.isEmpty else { return }
        entries = (entries + new).sorted { $0.createdAt > $1.createdAt }
        save()
    }

    @MainActor
    private func send(_ batch: [LogEntry]) async {
        for entry in batch {
            do {
                try await sync.push(entry)
                unsent.remove(entry.id)
            } catch {
                break  // Probably offline; the rest wait for the next refresh.
            }
        }
        save()
    }

    // MARK: Persistence

    private struct Saved: Codable {
        var entries: [LogEntry]
        var unsent: Set<UUID>
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try Self.encoder.encode(Saved(entries: entries, unsent: unsent)).write(to: fileURL, options: .atomic)
        } catch {
            print("IncidentLog: couldn't save — \(error)")
        }
    }

    private static func load(from url: URL?) -> Saved? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(Saved.self, from: data)
    }

    // Same JSON style as MapAnnotationStore, so a server can read both.
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
