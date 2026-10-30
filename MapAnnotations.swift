//
//  MapAnnotations.swift
//  MercyDrones — responder pins and boundaries
//
//  What responders add to the incident map by hand: category pins (people,
//  accelerants, gas leaks, anything else) and boundaries drawn corner by
//  corner. They're kept on the device for now (a JSON file in Documents), and
//  every change is also handed to a `MapAnnotationSync`, which does nothing
//  until a real backend is plugged in.
//
//  Drawing them on the map and handling taps lives in IncidentMap.swift; this
//  file has the data, the pin logos, and the sheets used to add and edit them.
//

import SwiftUI

// MARK: - Pin categories

enum PinCategory: String, CaseIterable, Identifiable, Codable {
    // Raw values are the sync wire format, so don't rename them.
    case personTrapped = "person_trapped"
    case personNotTrapped = "person_not_trapped"
    case accelerant
    case gasLeak = "gas_leak"
    case other
    var id: Self { self }

    var title: String {
        switch self {
        case .personTrapped:    return "Person · trapped"
        case .personNotTrapped: return "Person · not trapped"
        case .accelerant:       return "Accelerant"
        case .gasLeak:          return "Gas leak"
        case .other:            return "Other"
        }
    }

    /// Name drawn under the pin and in the legend.
    var shortName: String {
        switch self {
        case .personTrapped:    return "Trapped"
        case .personNotTrapped: return "Not trapped"
        default:                return title
        }
    }

    var color: Color {
        switch self {
        case .personTrapped:    return Theme.danger
        case .personNotTrapped: return Theme.blue
        case .accelerant:       return Color(light: 0xEA580C, dark: 0xFB923C)
        case .gasLeak:          return Color(light: 0xEAB308, dark: 0xFACC15)
        case .other:            return Theme.green
        }
    }

    /// White reads poorly on yellow, so the gas leak glyph is dark.
    var glyphColor: Color { self == .gasLeak ? Color(hex: 0x1F2937) : .white }
}

// MARK: - Pins and boundaries

struct HazardPin: Identifiable, Codable, Equatable {
    var id = UUID()
    var category: PinCategory
    /// What it is, typed by the responder. Only used (and required) for `.other`.
    var note = ""
    var coordinate: GeoPoint
    var createdAt = Date()

    var selectionID: String { "pin-\(id.uuidString)" }

    var marker: IncidentMarker {
        let coords = String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
        let time = createdAt.formatted(date: .omitted, time: .shortened)
        return IncidentMarker(id: selectionID,
                              kind: .hazard(category),
                              coordinate: coordinate,
                              title: category == .other ? note : category.title,
                              detail: "\(category == .other ? "Other · " : "")pinned \(time) · \(coords)",
                              shortName: category == .other ? Self.clipped(note) : category.shortName)
    }

    private static func clipped(_ text: String, to length: Int = 18) -> String {
        text.count > length ? String(text.prefix(length - 1)) + "…" : text
    }
}

struct IncidentBoundary: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    /// Corners in the order they were tapped.
    var points: [GeoPoint]
    /// Cover color as 0xRRGGBB so it syncs as a plain number.
    var colorHex: UInt32
    var createdAt = Date()

    var selectionID: String { "boundary-\(id.uuidString)" }
    var color: Color { Color(hex: colorHex) }
}

/// Cover colors offered for a boundary. Any other color can be picked as custom.
struct BoundaryCover: Identifiable {
    let name: String
    let hex: UInt32
    var id: UInt32 { hex }

    static let presets = [
        BoundaryCover(name: "Red", hex: 0xDC2626),
        BoundaryCover(name: "Orange", hex: 0xEA580C),
        BoundaryCover(name: "Yellow", hex: 0xEAB308)
    ]

    static func name(for hex: UInt32) -> String {
        presets.first { $0.hex == hex }?.name ?? "Custom"
    }
}

// MARK: - Storage and sync

/// Everything responders added to the map, as one syncable document.
struct MapAnnotationSnapshot: Codable, Equatable {
    var pins: [HazardPin] = []
    var boundaries: [IncidentBoundary] = []
    /// When this snapshot last changed. The newer copy wins when syncing.
    var updatedAt = Date.distantPast
}

/// Hook for sharing pins and boundaries with the rest of the crew.
///
/// To sync, write a type that talks to the backend (REST, Firebase, a drone
/// relay…) and pass it as `MapAnnotationStore(sync:)` in `MercyDronesApp`.
/// `push` runs after every local change with the full snapshot. `pull` runs
/// when the full-screen map opens; a snapshot newer than the local one
/// replaces it.
protocol MapAnnotationSync: Sendable {
    func push(_ snapshot: MapAnnotationSnapshot) async throws
    func pull() async throws -> MapAnnotationSnapshot?
}

/// The default: nothing leaves the device.
struct LocalOnlySync: MapAnnotationSync {
    func push(_ snapshot: MapAnnotationSnapshot) async throws {}
    func pull() async throws -> MapAnnotationSnapshot? { nil }
}

final class MapAnnotationStore: ObservableObject {
    @Published private(set) var snapshot: MapAnnotationSnapshot

    var pins: [HazardPin] { snapshot.pins }
    var boundaries: [IncidentBoundary] { snapshot.boundaries }
    var markers: [IncidentMarker] { pins.map(\.marker) }

    private let fileURL: URL?
    private let sync: MapAnnotationSync

    /// Pass `fileURL: nil` to keep everything in memory (previews).
    init(fileURL: URL? = URL.documentsDirectory.appending(path: "map-annotations.json"),
         sync: MapAnnotationSync = LocalOnlySync()) {
        self.fileURL = fileURL
        self.sync = sync
        snapshot = Self.load(from: fileURL) ?? MapAnnotationSnapshot()
    }

    @discardableResult
    func addPin(_ category: PinCategory, note: String = "", at coordinate: GeoPoint) -> HazardPin {
        let pin = HazardPin(category: category, note: note, coordinate: coordinate)
        change { $0.pins.append(pin) }
        return pin
    }

    func removePin(_ id: UUID) {
        change { $0.pins.removeAll { $0.id == id } }
    }

    @discardableResult
    func addBoundary(name: String, corners: [GeoPoint], colorHex: UInt32) -> IncidentBoundary {
        let boundary = IncidentBoundary(name: name, points: corners, colorHex: colorHex)
        change { $0.boundaries.append(boundary) }
        return boundary
    }

    func recolorBoundary(_ id: UUID, to colorHex: UInt32) {
        change { snapshot in
            if let i = snapshot.boundaries.firstIndex(where: { $0.id == id }) {
                snapshot.boundaries[i].colorHex = colorHex
            }
        }
    }

    func removeBoundary(_ id: UUID) {
        change { $0.boundaries.removeAll { $0.id == id } }
    }

    /// Pulls the crew's copy and keeps it if it's newer than ours.
    @MainActor
    func refresh() async {
        guard let remote = try? await sync.pull(), remote.updatedAt > snapshot.updatedAt else { return }
        snapshot = remote
        save()
    }

    private func change(_ edit: (inout MapAnnotationSnapshot) -> Void) {
        var next = snapshot
        edit(&next)
        next.updatedAt = Date()
        snapshot = next
        save()
        Task { [sync, next] in try? await sync.push(next) }
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try Self.encoder.encode(snapshot).write(to: fileURL, options: .atomic)
        } catch {
            print("MapAnnotationStore: couldn't save — \(error)")
        }
    }

    private static func load(from url: URL?) -> MapAnnotationSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(MapAnnotationSnapshot.self, from: data)
    }

    // ISO 8601 dates so the file reads the same on Android and a server.
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

// MARK: - Pin logos

/// The logo for each pin category: a white-ringed disc in the category color
/// with a glyph built from SF Symbols. Drawn with UIKit so Google pins, the
/// offline map and SwiftUI lists all share the same artwork.
enum HazardLogo {
    static func image(_ category: PinCategory, diameter: CGFloat,
                      traits: UITraitCollection = .current) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter)).image { _ in
            draw(category, in: CGRect(x: 0, y: 0, width: diameter, height: diameter), traits: traits)
        }
    }

    static func draw(_ category: PinCategory, in rect: CGRect, traits: UITraitCollection = .current) {
        let fill = UIColor(category.color).resolvedColor(with: traits)
        let ink = UIColor(category.glyphColor).resolvedColor(with: traits)
        let s = rect.width  // glyph sizes are fractions of the badge
        let center = CGPoint(x: rect.midX, y: rect.midY)

        UIColor.white.setFill()
        UIBezierPath(ovalIn: rect).fill()
        fill.setFill()
        UIBezierPath(ovalIn: rect.insetBy(dx: s * 0.08, dy: s * 0.08)).fill()

        switch category {
        case .personTrapped:
            // A person behind cage bars.
            symbol("person.fill", box: s * 0.4, color: ink, center: center)
            let bar = max(1.5, s * 0.05)
            let half = s * 0.19
            let top = center.y - s * 0.22
            let height = s * 0.44
            for dx in [-half, 0, half] {
                let line = CGRect(x: center.x + dx - bar / 2, y: top, width: bar, height: height)
                fill.setFill()  // thin gap so the bars read over the person
                UIBezierPath(rect: line.insetBy(dx: -bar * 0.6, dy: 0)).fill()
                ink.setFill()
                UIBezierPath(roundedRect: line, cornerRadius: bar / 2).fill()
            }
            for y in [top, top + height - bar] {
                let rail = CGRect(x: center.x - half - bar / 2, y: y, width: half * 2 + bar, height: bar)
                UIBezierPath(roundedRect: rail, cornerRadius: bar / 2).fill()
            }
        case .personNotTrapped:
            symbol("figure.walk", box: s * 0.5, color: ink, center: center)
        case .accelerant:
            // Fuel drop with a flame inside.
            symbol("drop.fill", box: s * 0.5, color: ink, center: CGPoint(x: center.x, y: center.y - s * 0.02))
            symbol("flame.fill", box: s * 0.2, color: fill, center: CGPoint(x: center.x, y: center.y + s * 0.07))
        case .gasLeak:
            symbol("smoke.fill", box: s * 0.52, color: ink, center: center)
        case .other:
            symbol("tag.fill", box: s * 0.42, color: ink, center: center)
        }
    }

    /// Draws an SF Symbol tinted `color`, scaled to fit a `box`-point square around `center`.
    private static func symbol(_ name: String, box: CGFloat, color: UIColor, center: CGPoint) {
        let config = UIImage.SymbolConfiguration(pointSize: 64, weight: .bold)
        guard let image = UIImage(systemName: name, withConfiguration: config)?
            .withTintColor(color, renderingMode: .alwaysOriginal) else { return }
        let scale = box / max(image.size.width, image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        image.draw(in: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                              width: size.width, height: size.height))
    }
}

/// A category's logo for use in SwiftUI.
struct HazardBadge: View {
    let category: PinCategory
    var diameter: CGFloat = 32
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        Image(uiImage: HazardLogo.image(category, diameter: diameter, traits: traits))
            .accessibilityLabel(category.title)
    }
}

// MARK: - Sheets and cards

/// Shown after tapping the map in pin mode: pick what's there.
struct NewPinSheet: View {
    let coordinate: GeoPoint
    let onSave: (PinCategory, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var category: PinCategory?
    @State private var note = ""
    @FocusState private var noteFocused: Bool

    private var trimmedNote: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSave: Bool {
        guard let category else { return false }
        return category != .other || !trimmedNote.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Drop a pin").font(.title2.weight(.bold)).foregroundColor(Theme.textPrimary)
                    Text(String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude))
                        .font(.subheadline.monospaced())
                        .foregroundColor(Theme.textSecondary)
                }

                Card(padding: 4) {
                    ForEach(PinCategory.allCases) { option in
                        let selected = category == option
                        Button { category = option } label: {
                            HStack(spacing: 12) {
                                HazardBadge(category: option, diameter: 36)
                                Text(option.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(Theme.textPrimary)
                                Spacer()
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundColor(selected ? option.color : Theme.textSecondary)
                            }
                            .padding(10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }

                if category == .other {
                    TextField("What is it? e.g. downed power line", text: $note)
                        .focused($noteFocused)
                        .submitLabel(.done)
                        .onAppear { noteFocused = true }
                        .padding(.horizontal, 14)
                        .frame(height: 52)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(PinCategory.other.color, lineWidth: 1.5))
                }

                HStack(spacing: 10) {
                    Button { dismiss() } label: { ActionLabel(title: "Cancel", style: .secondary) }
                    Button {
                        guard let category else { return }
                        onSave(category, category == .other ? trimmedNote : "")
                        dismiss()
                    } label: { ActionLabel(title: "Save pin", icon: "mappin") }
                    .disabled(!canSave)
                    .opacity(canSave ? 1 : 0.45)
                }
            }
            .padding(20)
        }
        .background(Theme.background.ignoresSafeArea())
        .presentationDetents([.large])
    }
}

/// Shown after the corners are placed: name the boundary and pick its cover.
struct BoundaryCoverSheet: View {
    let cornerCount: Int
    let onSave: (String, UInt32) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var colorHex = BoundaryCover.presets[0].hex

    init(defaultName: String, cornerCount: Int, onSave: @escaping (String, UInt32) -> Void) {
        self.cornerCount = cornerCount
        self.onSave = onSave
        _name = State(initialValue: defaultName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("New boundary").font(.title2.weight(.bold)).foregroundColor(Theme.textPrimary)
                Text("\(cornerCount) corners").font(.subheadline).foregroundColor(Theme.textSecondary)
            }

            TextField("Name", text: $name)
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.blue, lineWidth: 1.5))

            SectionHeader(title: "Cover", trailing: BoundaryCover.name(for: colorHex))
            BoundaryCoverPicker(hex: $colorHex)

            Spacer()

            HStack(spacing: 10) {
                Button { dismiss() } label: { ActionLabel(title: "Back", style: .secondary) }
                Button {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(trimmed.isEmpty ? "Boundary" : trimmed, colorHex)
                    dismiss()
                } label: { ActionLabel(title: "Save boundary", style: .green) }
            }
        }
        .padding(20)
        .background(Theme.background.ignoresSafeArea())
        .presentationDetents([.medium])
    }
}

/// Red, orange and yellow swatches plus a custom color well.
struct BoundaryCoverPicker: View {
    @Binding var hex: UInt32

    var body: some View {
        HStack(spacing: 12) {
            ForEach(BoundaryCover.presets) { cover in
                let selected = cover.hex == hex
                Button { hex = cover.hex } label: {
                    Circle()
                        .fill(Color(hex: cover.hex).opacity(0.3))
                        .overlay(Circle().stroke(Color(hex: cover.hex), lineWidth: 3))
                        .overlay {
                            if selected {
                                Image(systemName: "checkmark").font(.caption.weight(.bold))
                                    .foregroundColor(Color(hex: cover.hex))
                            }
                        }
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(cover.name)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }

            ColorPicker("Custom", selection: Binding(get: { Color(hex: hex) },
                                                     set: { hex = UIColor($0).hexValue }),
                        supportsOpacity: false)
                .fixedSize()
                .font(.subheadline)
                .foregroundColor(Theme.textSecondary)
            Spacer(minLength: 0)
        }
    }
}

struct BoundaryDetailCard: View {
    let boundary: IncidentBoundary
    let onRecolor: (UInt32) -> Void
    let onDelete: () -> Void
    let onClose: () -> Void
    @State private var confirmingDelete = false

    var body: some View {
        Card(padding: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "hexagon.fill")
                    .foregroundColor(boundary.color)
                    .frame(width: 36, height: 36)
                    .background(boundary.color.opacity(0.18))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(boundary.name).font(.subheadline.weight(.semibold)).foregroundColor(Theme.textPrimary)
                    Text("\(boundary.points.count) corners · \(BoundaryCover.name(for: boundary.colorHex).lowercased()) cover")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                DeleteButton(label: "Delete boundary") { confirmingDelete = true }
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Close details")
            }
            BoundaryCoverPicker(hex: Binding(get: { boundary.colorHex }, set: onRecolor))
        }
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .confirmationDialog("Delete \(boundary.name)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete boundary", role: .destructive, action: onDelete)
        }
    }
}

/// Small trash button used in the map detail cards.
struct DeleteButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.caption.weight(.bold))
                .foregroundColor(Theme.danger)
                .frame(width: 32, height: 32)
        }
        .accessibilityLabel(label)
    }
}

extension UIColor {
    /// 0xRRGGBB, clamped to sRGB.
    var hexValue: UInt32 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> UInt32 { UInt32((min(max(v, 0), 1) * 255).rounded()) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }
}
