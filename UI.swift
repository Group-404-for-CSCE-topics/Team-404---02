//
//  UI.swift
//  MercyDrones — first responder console (UI prototype only)
//
//  Built from mercydrones-wireframes.html. Every button is a placeholder:
//  no flight control, networking, camera, or payload logic is implemented.
//  The only state here is UI state (selected tab, toggles, drone names).
//  The exception is the live map, which lives in IncidentMap.swift.
//
//  Requires iOS 18+. The map uses the Google Maps SDK (see IncidentMap.swift
//  and the README for the API key setup).
//

import SwiftUI

// MARK: - App entry

@main
struct MercyDronesApp: App {
    @StateObject private var store = PrototypeStore()
    @AppStorage("appearance") private var appearance: Appearance = .system

    init() {
        GoogleMapsConfig.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(store)
                .preferredColorScheme(appearance.colorScheme)
                .tint(Theme.blue)
        }
    }
}

// MARK: - Theme (blue + green, light and dark)

enum Theme {
    static let blue          = Color(light: 0x1F6FEB, dark: 0x4C9AFF)
    static let green         = Color(light: 0x15924A, dark: 0x34D399)
    static let background    = Color(light: 0xF3F6FA, dark: 0x0A111E)
    static let surface       = Color(light: 0xFFFFFF, dark: 0x131C2D)
    static let surfaceAlt    = Color(light: 0xE6EDF6, dark: 0x1C2840)
    static let border        = Color(light: 0xD5DEEA, dark: 0x26344F)
    static let textPrimary   = Color(light: 0x0F172A, dark: 0xE6EDF7)
    static let textSecondary = Color(light: 0x5A6779, dark: 0x93A1B5)
    // Semantic colors, used sparingly for fire, urgency and low battery.
    static let warning       = Color(light: 0xC2620A, dark: 0xF59E0B)
    static let danger        = Color(light: 0xD02C2C, dark: 0xF87171)

    static let brandGradient = LinearGradient(colors: [blue, green], startPoint: .leading, endPoint: .trailing)
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }

    var title: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

extension Color {
    /// A color that resolves differently in light and dark mode.
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    init(hex: UInt32) {
        self.init(UIColor(hex: hex))
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - Prototype state

enum AppTab: Hashable {
    case fleet, map, aid, alerts, team
}

enum DroneStatus: String {
    case inFlight = "In flight"
    case docked = "Docked"
    case charging = "Charging"

    var color: Color {
        switch self {
        case .inFlight: return Theme.green
        case .docked:   return Theme.blue
        case .charging: return Theme.warning
        }
    }
}

struct Drone: Identifiable, Equatable {
    let id: String
    var name: String
    var status: DroneStatus
    var battery: Int
}

/// Holds UI-only state shared across tabs (drone callsigns show up everywhere).
final class PrototypeStore: ObservableObject {
    @Published var drones: [Drone] = [
        Drone(id: "MD-01", name: "Ember", status: .inFlight, battery: 82),
        Drone(id: "MD-02", name: "Ash", status: .docked, battery: 64),
        Drone(id: "MD-03", name: "Ridge", status: .charging, battery: 27)
    ]
    @Published var selectedTab: AppTab = .fleet
    @Published var renaming: Drone?

    func name(at index: Int) -> String {
        drones.indices.contains(index) ? drones[index].name : "—"
    }

    func rename(_ id: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = drones.firstIndex(where: { $0.id == id }) else { return }
        drones[i].name = trimmed
    }
}

// MARK: - Root navigation (five tabs, one job each)

struct RootTabView: View {
    @EnvironmentObject private var store: PrototypeStore

    var body: some View {
        TabView(selection: $store.selectedTab) {
            NavigationStack { FleetView() }
                .tabItem { Label("Fleet", systemImage: "airplane.circle") }
                .tag(AppTab.fleet)

            NavigationStack { LiveMapView() }
                .tabItem { Label("Map", systemImage: "map") }
                .tag(AppTab.map)

            NavigationStack { AidDeliveryView() }
                .tabItem { Label("Aid", systemImage: "shippingbox") }
                .tag(AppTab.aid)

            NavigationStack { AlertsView() }
                .tabItem { Label("Alerts", systemImage: "bell") }
                .tag(AppTab.alerts)

            NavigationStack { TeamView() }
                .tabItem { Label("Team", systemImage: "person.3") }
                .tag(AppTab.team)
        }
        .sheet(item: $store.renaming) { drone in
            RenameDroneSheet(drone: drone)
                .environmentObject(store)
        }
    }
}

// MARK: - Shared components

/// Scrolling screen with a subtitle, themed background, appearance menu,
/// and an optional pinned bottom action (primary actions sit at thumb height).
struct ScreenScaffold<Content: View, Bottom: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content
    @ViewBuilder var bottom: Bottom

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(Theme.textSecondary)
                content
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(title)
        .safeAreaInset(edge: .bottom) { bottom }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { AppearanceMenu() }
        }
    }
}

extension ScreenScaffold where Bottom == EmptyView {
    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
        self.bottom = EmptyView()
    }
}

/// Wraps pinned bottom buttons in a translucent bar.
struct BottomActionBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 10) { content }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(.ultraThinMaterial)
    }
}

struct AppearanceMenu: View {
    @AppStorage("appearance") private var appearance: Appearance = .system

    var body: some View {
        Menu {
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { option in
                    Label(option.title, systemImage: option.icon).tag(option)
                }
            }
        } label: {
            Image(systemName: appearance.icon)
        }
        .accessibilityLabel("Appearance")
    }
}

enum ActionStyle {
    case blue, green, secondary
}

/// Label used for full-width actions, so it works inside Button or NavigationLink.
struct ActionLabel: View {
    let title: String
    var icon: String? = nil
    var style: ActionStyle = .blue

    var body: some View {
        HStack(spacing: 8) {
            if let icon = icon { Image(systemName: icon) }
            Text(title)
        }
        .font(.headline)
        .frame(maxWidth: .infinity, minHeight: 52)
        .foregroundColor(style == .secondary ? Theme.blue : .white)
        .background(fill)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(style == .secondary ? Theme.blue.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
    }

    @ViewBuilder private var fill: some View {
        switch style {
        case .blue:      Theme.blue
        case .green:     Theme.green
        case .secondary: Theme.surface
        }
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(0.8)
                .foregroundColor(Theme.textSecondary)
            Spacer()
            if let trailing = trailing {
                Text(trailing).font(.caption).foregroundColor(Theme.textSecondary)
            }
        }
        .padding(.top, 4)
    }
}

struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundColor(color)
            .background(color.opacity(0.14))
            .clipShape(Capsule())
    }
}

/// AI output always carries its confidence next to it.
struct ConfidenceBadge: View {
    let value: Double

    var body: some View {
        let color = value >= 0.8 ? Theme.green : (value >= 0.6 ? Theme.blue : Theme.warning)
        return Text(String(format: "%.2f", value))
            .font(.caption.monospacedDigit().weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundColor(color)
            .overlay(Capsule().stroke(color, lineWidth: 1))
    }
}

struct BatteryBar: View {
    let level: Int

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.surfaceAlt)
                Capsule()
                    .fill(level < 30 ? Theme.warning : Theme.green)
                    .frame(width: geo.size.width * CGFloat(level) / 100)
            }
        }
        .frame(height: 6)
    }
}

struct SelectableRow: View {
    let title: String
    var detail: String? = nil
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isOn ? Theme.green : Theme.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundColor(Theme.textPrimary)
                    if let detail = detail {
                        Text(detail).font(.caption).foregroundColor(Theme.textSecondary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Faint grid that stands in for a real map tile layer.
struct MapGrid: Shape {
    var spacing: CGFloat = 22

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x: CGFloat = 0
        while x <= rect.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
            x += spacing
        }
        var y: CGFloat = 0
        while y <= rect.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
            y += spacing
        }
        return path
    }
}

struct MapPlaceholder<Overlay: View>: View {
    var height: CGFloat = 280
    @ViewBuilder var overlay: Overlay

    var body: some View {
        ZStack {
            Theme.surfaceAlt
            MapGrid().stroke(Theme.border, lineWidth: 0.6)
            overlay
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

// MARK: - 01 Fleet

struct FleetView: View {
    @EnvironmentObject private var store: PrototypeStore
    @State private var search = ""

    var body: some View {
        ScreenScaffold(title: "Fleet", subtitle: "3 drones · station 12") {
            HStack(spacing: 10) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(Theme.textSecondary)
                    TextField("Search fleet…", text: $search)
                }
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border, lineWidth: 1))

                Button {} label: {
                    Label("Filter", systemImage: "line.3.horizontal.decrease")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border, lineWidth: 1))
                }
            }

            SectionHeader(title: "\(store.drones.count) drones · 1 in flight")

            ForEach(store.drones) { drone in
                DroneCard(drone: drone)
            }
        } bottom: {
            BottomActionBar {
                NavigationLink {
                    MissionSetupView()
                } label: {
                    ActionLabel(title: "Start new mission", icon: "plus")
                }
            }
        }
    }
}

struct DroneCard: View {
    @EnvironmentObject private var store: PrototypeStore
    let drone: Drone

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.brandGradient)
                        .frame(width: 46, height: 46)
                    Image(systemName: "airplane")
                        .font(.title3)
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Button { store.renaming = drone } label: {
                        HStack(spacing: 5) {
                            Text(drone.name).font(.headline).foregroundColor(Theme.textPrimary)
                            Image(systemName: "pencil").font(.caption).foregroundColor(Theme.blue)
                        }
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 6) {
                        Text(drone.id).font(.caption.monospaced()).foregroundColor(Theme.textSecondary)
                        StatusPill(text: drone.status.rawValue, color: drone.status.color)
                    }
                }

                Spacer()

                Button("View") { store.selectedTab = .map }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Image(systemName: drone.battery < 30 ? "battery.25" : "battery.75")
                    .foregroundColor(drone.battery < 30 ? Theme.warning : Theme.green)
                BatteryBar(level: drone.battery)
                Text("\(drone.battery)%")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(Theme.textSecondary)
            }
        }
    }
}

// MARK: - 02 Mission setup

enum IncidentType: String, CaseIterable, Identifiable {
    case wildfire = "Wildfire"
    case earthquake = "Earthquake"
    case flood = "Flood"
    case other = "Other"
    var id: Self { self }

    var icon: String {
        switch self {
        case .wildfire:   return "flame"
        case .earthquake: return "waveform.path.ecg"
        case .flood:      return "drop"
        case .other:      return "questionmark.circle"
        }
    }
}

struct MissionSetupView: View {
    @EnvironmentObject private var store: PrototypeStore
    @Environment(\.dismiss) private var dismiss
    @State private var incident: IncidentType?
    @State private var areaDrawn = false
    @State private var assigned: Set<String> = []

    private var completedSteps: Int {
        if incident == nil { return 0 }
        if !areaDrawn { return 1 }
        return assigned.isEmpty ? 2 : 3
    }

    var body: some View {
        ScreenScaffold(title: "New mission", subtitle: "step \(min(completedSteps + 1, 3)) of 3") {
            StepIndicator(steps: ["Type", "Area", "Crew"], completed: completedSteps)

            SectionHeader(title: "Incident type")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(IncidentType.allCases) { type in
                    let selected = incident == type
                    Button { incident = type } label: {
                        VStack(spacing: 8) {
                            Image(systemName: type.icon).font(.title2)
                            Text(type.rawValue).font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 84)
                        .foregroundColor(selected ? .white : Theme.textPrimary)
                        .background(selected ? Theme.blue : Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(selected ? Theme.blue : Theme.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }

            SectionHeader(title: "Search area")
            Button { areaDrawn.toggle() } label: {
                MapPlaceholder(height: 170) {
                    if areaDrawn {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Theme.green, style: StrokeStyle(lineWidth: 2.5, dash: [8, 5]))
                            .background(Theme.green.opacity(0.12))
                            .padding(30)
                        Text("ZONE A · 2.4 mi²")
                            .font(.caption.weight(.bold))
                            .foregroundColor(Theme.green)
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "hand.draw").font(.title)
                            Text("Tap to draw area on map").font(.subheadline)
                        }
                        .foregroundColor(Theme.textSecondary)
                    }
                }
            }
            .buttonStyle(.plain)

            SectionHeader(title: "Assign drones")
            Card(padding: 10) {
                ForEach(store.drones) { drone in
                    SelectableRow(title: drone.name,
                                  detail: "\(drone.id) · batt \(drone.battery)%",
                                  isOn: assigned.contains(drone.id)) {
                        if assigned.contains(drone.id) { assigned.remove(drone.id) } else { assigned.insert(drone.id) }
                    }
                }
            }
        } bottom: {
            BottomActionBar {
                Button {
                    dismiss()
                    store.selectedTab = .map
                } label: {
                    ActionLabel(title: "Launch mission", icon: "paperplane.fill", style: .green)
                }
                .disabled(completedSteps < 3)
                .opacity(completedSteps < 3 ? 0.45 : 1)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct StepIndicator: View {
    let steps: [String]
    let completed: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                let done = index < completed
                let current = index == completed
                HStack(spacing: 6) {
                    ZStack {
                        Circle()
                            .fill(done ? Theme.green : (current ? Theme.blue : Color.clear))
                            .frame(width: 26, height: 26)
                            .overlay(Circle().stroke(done || current ? Color.clear : Theme.border, lineWidth: 1.5))
                        if done {
                            Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundColor(.white)
                        } else {
                            Text("\(index + 1)").font(.caption.weight(.bold))
                                .foregroundColor(current ? .white : Theme.textSecondary)
                        }
                    }
                    Text(step.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundColor(done || current ? Theme.textPrimary : Theme.textSecondary)
                }
                if index < steps.count - 1 {
                    Rectangle()
                        .fill(done ? Theme.green : Theme.border)
                        .frame(height: 2)
                        .padding(.horizontal, 8)
                }
            }
        }
    }
}

// MARK: - 03 / 04a / 04b Live map (Overview · Fire · Victims)

enum MapMode: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case fire = "Fire"
    case victims = "Victims"
    var id: Self { self }
}

struct LiveMapView: View {
    @EnvironmentObject private var store: PrototypeStore
    @State private var mode: MapMode = .overview

    private var subtitle: String {
        switch mode {
        case .overview: return "wildfire · elapsed 00:18:42"
        case .fire:     return "thermal overlay + spread prediction"
        case .victims:  return "onboard camera · \(store.name(at: 0))"
        }
    }

    var body: some View {
        ScreenScaffold(title: "Zone A · live", subtitle: subtitle) {
            Picker("View", selection: $mode) {
                ForEach(MapMode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            switch mode {
            case .overview: OverviewContent()
            case .fire:     FireContent()
            case .victims:  VictimContent()
            }
        } bottom: {
            BottomActionBar {
                switch mode {
                case .overview:
                    Button { store.selectedTab = .aid } label: {
                        ActionLabel(title: "Send aid to selected point", icon: "shippingbox.fill", style: .green)
                    }
                case .fire:
                    HStack(spacing: 10) {
                        Button {} label: { ActionLabel(title: "Save snapshot", icon: "camera", style: .secondary) }
                        Button {} label: { ActionLabel(title: "Send to team", icon: "paperplane.fill") }
                    }
                case .victims:
                    Button { store.selectedTab = .aid } label: {
                        ActionLabel(title: "Deliver aid to Victim 01", icon: "shippingbox.fill", style: .green)
                    }
                }
            }
        }
    }
}

struct OverviewContent: View {
    var body: some View {
        IncidentMapCard()
        MapLegend()

        HStack(spacing: 10) {
            StatTile(label: "Wind", value: "14 mph NE", icon: "wind")
            StatTile(label: "Area", value: "2.4 mi²", icon: "square.dashed")
            StatTile(label: "Elapsed", value: "00:18:42", icon: "clock")
        }
    }
}

struct LegendItem: View {
    let symbol: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).foregroundColor(color)
            Text(label).foregroundColor(Theme.textSecondary)
        }
    }
}

struct StatTile: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label.uppercased(), systemImage: icon)
                .font(.caption2.weight(.semibold))
                .foregroundColor(Theme.textSecondary)
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundColor(Theme.textPrimary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }
}

struct FireContent: View {
    @EnvironmentObject private var store: PrototypeStore

    var body: some View {
        // Thermal imagery stays dark in both modes, like a real IR feed.
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let origin = CGPoint(x: w * 0.36, y: h * 0.64)
            let cone = Path { p in
                p.move(to: origin)
                p.addLine(to: CGPoint(x: w * 0.86, y: h * 0.06))
                p.addLine(to: CGPoint(x: w * 0.97, y: h * 0.42))
                p.closeSubpath()
            }
            ZStack {
                LinearGradient(colors: [Color(hex: 0x121A2E), Color(hex: 0x24183A)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                MapGrid(spacing: 26).stroke(Color.white.opacity(0.06), lineWidth: 0.6)

                cone.fill(Color(hex: 0xF59E0B).opacity(0.16))
                cone.stroke(Color(hex: 0xF59E0B), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))

                Ellipse()
                    .fill(RadialGradient(colors: [Color(hex: 0xFFF3B0), Color(hex: 0xFF8A00), Color(hex: 0xE11D48).opacity(0)],
                                         center: .center, startRadius: 4, endRadius: 80))
                    .frame(width: 170, height: 120)
                    .position(origin)

                Text("ACTIVE BURN")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(.white)
                    .position(x: origin.x, y: origin.y + 70)
                Text("predicted +30 min")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(Color(hex: 0xFCD34D))
                    .position(x: w * 0.78, y: h * 0.5)

                Label("wind 14 mph", systemImage: "arrow.up.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Capsule())
                    .position(x: w * 0.2, y: h * 0.12)
            }
        }
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

        Card {
            HStack {
                Label("AI assessment", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundColor(Theme.textPrimary)
                Spacer()
                ConfidenceBadge(value: 0.86)
            }
            Text("Spread heading NE toward tree line. Two structures inside the 30-minute cone.")
                .font(.subheadline)
                .foregroundColor(Theme.textPrimary)
            Text("confidence 0.86 · source \(store.name(at: 0))")
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
        }
    }
}

struct VictimContent: View {
    @EnvironmentObject private var store: PrototypeStore
    @State private var marked: Set<Int> = []

    private let detections = Detection.zoneA

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: [Color(hex: 0x1D2433), Color(hex: 0x0B0F17)],
                               startPoint: .top, endPoint: .bottom)

                DetectionBox(label: "PERSON 0.94", color: Color(hex: 0x34D399), dashed: false)
                    .frame(width: w * 0.24, height: h * 0.42)
                    .position(x: w * 0.34, y: h * 0.52)
                DetectionBox(label: "POSSIBLE 0.51", color: Color(hex: 0xF59E0B), dashed: true)
                    .frame(width: w * 0.18, height: h * 0.3)
                    .position(x: w * 0.74, y: h * 0.6)

                HStack(spacing: 6) {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                    Text("LIVE · \(store.name(at: 0))").font(.caption2.weight(.bold))
                }
                .foregroundColor(.white)
                .padding(8)

                Text("IR · 34.05°N 118.24°W")
                    .font(.caption2.monospaced())
                    .foregroundColor(.white.opacity(0.8))
                    .position(x: w - 82, y: h - 14)
            }
        }
        .frame(height: 240)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

        SectionHeader(title: "Detections (\(detections.count))", trailing: "sort: confidence")

        ForEach(detections) { d in
            Card(padding: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "person.fill")
                        .foregroundColor(Theme.blue)
                        .frame(width: 36, height: 36)
                        .background(Theme.blue.opacity(0.12))
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(d.title).font(.subheadline.weight(.semibold)).foregroundColor(Theme.textPrimary)
                        Text(d.coords).font(.caption.monospaced()).foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    ConfidenceBadge(value: d.confidence)
                    Button(marked.contains(d.id) ? "Marked" : "Mark") {
                        if marked.contains(d.id) { marked.remove(d.id) } else { marked.insert(d.id) }
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .tint(marked.contains(d.id) ? Theme.green : Theme.blue)
                }
            }
        }
    }
}

struct DetectionBox: View {
    let label: String
    let color: Color
    let dashed: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .stroke(color, style: StrokeStyle(lineWidth: 2, dash: dashed ? [6, 4] : []))
            .overlay(alignment: .topLeading) {
                Text(label)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(color)
                    .offset(y: -16)
            }
    }
}

// MARK: - 05 Aid delivery

struct Payload: Identifiable {
    let id: String
    let icon: String
    let weight: Double
}

enum DropMethod: String, CaseIterable, Identifiable {
    case winch = "Winch down"
    case release = "Release"
    var id: Self { self }
}

struct AidDeliveryView: View {
    @EnvironmentObject private var store: PrototypeStore
    @State private var selected: Set<String> = ["Water · 1.5 L", "Trauma kit"]
    @State private var method: DropMethod = .winch

    private let payloads = [
        Payload(id: "Water · 1.5 L", icon: "drop.fill", weight: 1.5),
        Payload(id: "Trauma kit", icon: "cross.case.fill", weight: 0.9),
        Payload(id: "Thermal blanket", icon: "thermometer.sun.fill", weight: 0.3),
        Payload(id: "Radio beacon", icon: "antenna.radiowaves.left.and.right", weight: 0.4)
    ]
    private let capacity = 3.0

    private var bayWeight: Double {
        payloads.filter { selected.contains($0.id) }.reduce(0) { $0 + $1.weight }
    }

    var body: some View {
        ScreenScaffold(title: "Aid delivery", subtitle: "payload bay") {
            Card {
                HStack(spacing: 12) {
                    Image(systemName: "scope")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 46, height: 46)
                        .background(Theme.brandGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Target: Victim 01").font(.headline).foregroundColor(Theme.textPrimary)
                        Text("34.0501, -118.2402 · carrier \(store.name(at: 0)) · 240 m away")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }
                }
            }

            SectionHeader(title: "Payload bay")
            Card(padding: 10) {
                ForEach(payloads) { item in
                    SelectableRow(title: item.id,
                                  detail: String(format: "%.1f kg", item.weight),
                                  isOn: selected.contains(item.id)) {
                        if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
                    }
                }
                Divider()
                HStack {
                    Text("Bay weight").font(.caption).foregroundColor(Theme.textSecondary)
                    Spacer()
                    Text(String(format: "%.1f / %.1f kg", bayWeight, capacity))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundColor(bayWeight > capacity ? Theme.danger : Theme.textPrimary)
                }
                ProgressView(value: min(bayWeight, capacity), total: capacity)
                    .tint(bayWeight > capacity ? Theme.danger : Theme.green)
            }

            SectionHeader(title: "Drop method")
            Picker("Drop method", selection: $method) {
                ForEach(DropMethod.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Label("Hold-to-confirm prevents accidental drops", systemImage: "info.circle")
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
        } bottom: {
            BottomActionBar {
                HoldToConfirmButton(title: "Hold to release payload")
            }
        }
    }
}

/// Visual-only hold-to-confirm. Fills while pressed; nothing is actually released.
struct HoldToConfirmButton: View {
    let title: String
    var duration: Double = 1.5
    @State private var progress: CGFloat = 0
    @State private var confirmed = false

    var body: some View {
        ZStack(alignment: .leading) {
            Theme.green
            GeometryReader { geo in
                Rectangle()
                    .fill(Color.white.opacity(0.28))
                    .frame(width: geo.size.width * progress)
            }
            HStack(spacing: 8) {
                Image(systemName: confirmed ? "checkmark.circle.fill" : "hand.tap.fill")
                Text(confirmed ? "Released (prototype only)" : title)
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onLongPressGesture(minimumDuration: duration, pressing: { pressing in
            if pressing {
                withAnimation(.linear(duration: duration)) { progress = 1 }
            } else if !confirmed {
                withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
            }
        }, perform: {
            confirmed = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                confirmed = false
                withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
            }
        })
        .accessibilityLabel(title)
    }
}

// MARK: - 06 Alerts & log

enum AlertFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case urgent = "Urgent"
    case mine = "Mine"
    var id: Self { self }
}

struct AlertItem: Identifiable {
    let id = UUID()
    let title: String
    let time: String
    let source: String
    let icon: String
    let color: Color
    let urgent: Bool
    let mine: Bool
}

struct AlertsView: View {
    @EnvironmentObject private var store: PrototypeStore
    @State private var filter: AlertFilter = .all

    private var items: [AlertItem] {
        [
            AlertItem(title: "Payload released — Victim 01", time: "14:22", source: "\(store.name(at: 0)) · water, trauma kit",
                      icon: "shippingbox.fill", color: Theme.green, urgent: false, mine: true),
            AlertItem(title: "Fire spread update sent to crew", time: "14:18", source: store.name(at: 0),
                      icon: "flame.fill", color: Theme.warning, urgent: true, mine: true),
            AlertItem(title: "3 victims detected in Zone A", time: "14:04", source: store.name(at: 1),
                      icon: "person.3.fill", color: Theme.danger, urgent: true, mine: false),
            AlertItem(title: "Battery below 30% — returning to base", time: "13:51", source: store.name(at: 2),
                      icon: "battery.25", color: Theme.warning, urgent: false, mine: false),
            AlertItem(title: "Mission launched · Wildfire · Zone A", time: "13:44", source: "dispatcher",
                      icon: "paperplane.fill", color: Theme.blue, urgent: false, mine: true)
        ]
    }

    private var filtered: [AlertItem] {
        switch filter {
        case .all:    return items
        case .urgent: return items.filter { $0.urgent }
        case .mine:   return items.filter { $0.mine }
        }
    }

    var body: some View {
        ScreenScaffold(title: "Alerts & log", subtitle: "incident 2043") {
            Picker("Filter", selection: $filter) {
                ForEach(AlertFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Card(padding: 4) {
                ForEach(Array(filtered.enumerated()), id: \.element.id) { index, item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.icon)
                            .foregroundColor(item.color)
                            .frame(width: 34, height: 34)
                            .background(item.color.opacity(0.14))
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(Theme.textPrimary)
                                if item.urgent { StatusPill(text: "Urgent", color: Theme.danger) }
                            }
                            Text("\(item.time) · \(item.source)")
                                .font(.caption)
                                .foregroundColor(Theme.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    if index < filtered.count - 1 { Divider().padding(.leading, 56) }
                }
            }
        } bottom: {
            BottomActionBar {
                Button {} label: {
                    ActionLabel(title: "Export incident log (PDF)", icon: "square.and.arrow.up", style: .secondary)
                }
            }
        }
    }
}

// MARK: - 07 Team & roles

struct CrewMember: Identifiable {
    let id = UUID()
    let name: String
    let role: String
    let access: String
    let color: Color
}

struct TeamView: View {
    @EnvironmentObject private var store: PrototypeStore
    @AppStorage("appearance") private var appearance: Appearance = .system

    private let crew = [
        CrewMember(name: "C. Reardon", role: "Incident commander", access: "full control", color: Theme.blue),
        CrewMember(name: "J. Harper", role: "Pilot", access: "flight + payload", color: Theme.green),
        CrewMember(name: "Station 12 crew (6)", role: "Viewer", access: "map + alerts only", color: Theme.textSecondary)
    ]

    var body: some View {
        ScreenScaffold(title: "Team & roles", subtitle: "station 12") {
            SectionHeader(title: "Crew on this incident")
            Card(padding: 4) {
                ForEach(Array(crew.enumerated()), id: \.element.id) { index, member in
                    HStack(spacing: 12) {
                        Text(String(member.name.prefix(1)))
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(width: 38, height: 38)
                            .background(member.color)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(member.name).font(.subheadline.weight(.semibold)).foregroundColor(Theme.textPrimary)
                            Text("\(member.role) · \(member.access)").font(.caption).foregroundColor(Theme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(Theme.textSecondary)
                    }
                    .padding(10)
                    if index < crew.count - 1 { Divider().padding(.leading, 60) }
                }
            }

            SectionHeader(title: "Drone names")
            Card(padding: 4) {
                ForEach(store.drones) { drone in
                    Button { store.renaming = drone } label: {
                        HStack {
                            Image(systemName: "airplane").foregroundColor(Theme.blue)
                            Text(drone.name).font(.subheadline.weight(.semibold)).foregroundColor(Theme.textPrimary)
                            Text(drone.id).font(.caption.monospaced()).foregroundColor(Theme.textSecondary)
                            Spacer()
                            Text("Edit").font(.subheadline).foregroundColor(Theme.blue)
                        }
                        .padding(12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Callsigns are spoken over radio, so keep them short.")
                .font(.caption)
                .foregroundColor(Theme.textSecondary)

            SectionHeader(title: "Appearance")
            Picker("Appearance", selection: $appearance) {
                ForEach(Appearance.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        } bottom: {
            BottomActionBar {
                Button {} label: { ActionLabel(title: "Invite responder", icon: "person.badge.plus") }
            }
        }
    }
}

// MARK: - Rename drone sheet

struct RenameDroneSheet: View {
    @EnvironmentObject private var store: PrototypeStore
    @Environment(\.dismiss) private var dismiss
    let drone: Drone
    @State private var value: String

    private let suggestions = ["Ember", "Ash", "Ridge", "Kestrel"]

    init(drone: Drone) {
        self.drone = drone
        _value = State(initialValue: drone.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Rename drone").font(.title2.weight(.bold)).foregroundColor(Theme.textPrimary)
                Text("\(drone.id) · visible to the whole crew").font(.subheadline).foregroundColor(Theme.textSecondary)
            }

            TextField("Callsign", text: $value)
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.blue, lineWidth: 1.5))

            HStack(spacing: 8) {
                Text("Suggestions").font(.caption).foregroundColor(Theme.textSecondary)
                ForEach(suggestions, id: \.self) { name in
                    Button(name) { value = name }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .tint(Theme.green)
                }
            }

            Spacer()

            HStack(spacing: 10) {
                Button { dismiss() } label: { ActionLabel(title: "Cancel", style: .secondary) }
                Button {
                    store.rename(drone.id, to: value)
                    dismiss()
                } label: { ActionLabel(title: "Save name") }
            }
        }
        .padding(20)
        .background(Theme.background.ignoresSafeArea())
        .presentationDetents([.medium])
    }
}

// MARK: - Previews

struct MercyDrones_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            RootTabView()
                .preferredColorScheme(.light)
                .previewDisplayName("Light")
            RootTabView()
                .preferredColorScheme(.dark)
                .previewDisplayName("Dark")
        }
        .environmentObject(PrototypeStore())
        .tint(Theme.blue)
    }
}
