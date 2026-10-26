//
//  IncidentMap.swift
//  MercyDrones — live incident map
//
//  Everything map-related lives here: Zone A's coordinates, the markers built
//  from the fleet, the in-page map card and the full-screen map. Positions are
//  fixed prototype coordinates, but the map itself is real MapKit: it can show
//  the responder's location and hand off to Apple Maps for directions.
//
//  Shared styling (Theme, Card, ActionLabel, LegendItem) comes from UI.swift.
//

import SwiftUI
import MapKit
import CoreLocation

// MARK: - Zone A data

/// Fixed prototype coordinates for Zone A (same area as the victim detections).
enum IncidentSite {
    static let center = CLLocationCoordinate2D(latitude: 34.0502, longitude: -118.2403)
    static let region = MKCoordinateRegion(center: center, latitudinalMeters: 900, longitudinalMeters: 900)

    static let searchZone = [
        CLLocationCoordinate2D(latitude: 34.0519, longitude: -118.2429),
        CLLocationCoordinate2D(latitude: 34.0521, longitude: -118.2382),
        CLLocationCoordinate2D(latitude: 34.0487, longitude: -118.2376),
        CLLocationCoordinate2D(latitude: 34.0483, longitude: -118.2424)
    ]

    static let dronePositions = [
        "MD-01": CLLocationCoordinate2D(latitude: 34.0509, longitude: -118.2416),
        "MD-02": CLLocationCoordinate2D(latitude: 34.0493, longitude: -118.2389)
    ]
    static let hoveringDrones: Set<String> = ["MD-02"]
}

struct Detection: Identifiable {
    let id: Int
    let title: String
    let coordinate: CLLocationCoordinate2D
    let confidence: Double

    var coords: String { String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude) }

    /// Shared by the Victims list and the map markers.
    static let zoneA = [
        Detection(id: 1, title: "Victim 01 · behind rubble",
                  coordinate: CLLocationCoordinate2D(latitude: 34.0501, longitude: -118.2402), confidence: 0.94),
        Detection(id: 2, title: "Victim 02 · street level",
                  coordinate: CLLocationCoordinate2D(latitude: 34.0498, longitude: -118.2410), confidence: 0.71),
        Detection(id: 3, title: "Possible · near vehicle",
                  coordinate: CLLocationCoordinate2D(latitude: 34.0507, longitude: -118.2395), confidence: 0.51)
    ]
}

struct IncidentMarker: Identifiable {
    enum Kind { case drone, hoveringDrone, victim }

    let id: String
    let kind: Kind
    let coordinate: CLLocationCoordinate2D
    let title: String
    let detail: String

    /// Short name drawn on the map, e.g. "Victim 01" instead of the full title.
    var label: String { title.components(separatedBy: " · ").first ?? title }

    var icon: String {
        switch kind {
        case .drone:         return "airplane"
        case .hoveringDrone: return "pause.fill"
        case .victim:        return "person.fill"
        }
    }

    var color: Color { kind == .victim ? Theme.danger : Theme.blue }
}

extension PrototypeStore {
    /// Built on demand so renamed callsigns show up on the map.
    var incidentMarkers: [IncidentMarker] {
        let dronePins = drones.compactMap { drone -> IncidentMarker? in
            guard let position = IncidentSite.dronePositions[drone.id] else { return nil }
            let hovering = IncidentSite.hoveringDrones.contains(drone.id)
            return IncidentMarker(id: drone.id,
                                  kind: hovering ? .hoveringDrone : .drone,
                                  coordinate: position,
                                  title: drone.name,
                                  detail: "\(drone.id) · \(hovering ? "Hovering" : drone.status.rawValue) · batt \(drone.battery)%")
        }
        let victimPins = Detection.zoneA.map { d in
            IncidentMarker(id: "victim-\(d.id)",
                           kind: .victim,
                           coordinate: d.coordinate,
                           title: d.title,
                           detail: String(format: "%@ · confidence %.2f", d.coords, d.confidence))
        }
        return dronePins + victimPins
    }
}

enum MapLayer: String, CaseIterable, Identifiable {
    case standard = "Map"
    case satellite = "Satellite"
    case hybrid = "Hybrid"
    var id: Self { self }

    var style: MapStyle {
        switch self {
        case .standard:  return .standard(elevation: .realistic)
        case .satellite: return .imagery(elevation: .realistic)
        case .hybrid:    return .hybrid(elevation: .realistic)
        }
    }
}

// MARK: - Map

/// The map itself, shared by the in-page card and the full-screen view.
struct IncidentMap: View {
    let markers: [IncidentMarker]
    let layer: MapLayer
    @Binding var position: MapCameraPosition
    @Binding var selection: String?
    var interactive = true

    var body: some View {
        Map(position: $position, interactionModes: interactive ? .all : [], selection: $selection) {
            MapPolygon(coordinates: IncidentSite.searchZone)
                .foregroundStyle(Theme.green.opacity(0.12))
                .stroke(Theme.green, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))

            ForEach(markers) { marker in
                Marker(marker.label, systemImage: marker.icon, coordinate: marker.coordinate)
                    .tint(marker.color)
                    .tag(marker.id)
            }

            if interactive {
                UserAnnotation()
            }
        }
        .mapStyle(layer.style)
        .mapControls {
            if interactive {
                MapCompass()
                MapScaleView()
                MapPitchToggle()
            }
        }
    }
}

/// In-page map for the Overview. It stays still so the page scrolls normally;
/// tapping it opens the full-screen map for panning and zooming.
struct IncidentMapCard: View {
    @EnvironmentObject private var store: PrototypeStore
    @AppStorage("mapLayer") private var layer: MapLayer = .standard
    @State private var expanded = false

    var body: some View {
        Button { expanded = true } label: {
            IncidentMap(markers: store.incidentMarkers,
                        layer: layer,
                        position: .constant(.region(IncidentSite.region)),
                        selection: .constant(nil),
                        interactive: false)
                .allowsHitTesting(false)
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.border, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    Label("Expand", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(Theme.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(10)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Zone A map")
        .accessibilityHint("Opens the map full screen")
        .fullScreenCover(isPresented: $expanded) {
            FullScreenMapView()
                .environmentObject(store)
                .tint(Theme.blue)
        }
    }
}

/// Full-screen, fully interactive map so responders can see the wider area,
/// find themselves, and get directions to a victim or drone.
struct FullScreenMapView: View {
    @EnvironmentObject private var store: PrototypeStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("mapLayer") private var layer: MapLayer = .standard
    @State private var position: MapCameraPosition = .region(IncidentSite.region)
    @State private var selection: String?
    @State private var locationManager = CLLocationManager()

    private var selectedMarker: IncidentMarker? {
        store.incidentMarkers.first { $0.id == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            IncidentMap(markers: store.incidentMarkers, layer: layer, position: $position, selection: $selection)
                .safeAreaInset(edge: .bottom) {
                    HStack(alignment: .bottom, spacing: 12) {
                        if let marker = selectedMarker {
                            MarkerDetailCard(marker: marker) { selection = nil }
                        } else {
                            Spacer()
                        }
                        VStack(spacing: 10) {
                            MapControlButton(icon: "location.fill", label: "Show my location") {
                                withAnimation { position = .userLocation(fallback: .region(IncidentSite.region)) }
                            }
                            MapControlButton(icon: "scope", label: "Recenter on Zone A") {
                                withAnimation { position = .region(IncidentSite.region) }
                            }
                        }
                    }
                    .padding(16)
                }
        }
        .background(Theme.surface.ignoresSafeArea())
        .onAppear {
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestWhenInUseAuthorization()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Zone A · live").font(.headline).foregroundColor(Theme.textPrimary)
                    Text("tap a marker for details and directions")
                        .font(.caption)
                        .foregroundColor(Theme.textSecondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .foregroundColor(Theme.textPrimary)
                        .frame(width: 44, height: 44)
                        .background(Theme.surfaceAlt)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Close map")
            }

            Picker("Map style", selection: $layer) {
                ForEach(MapLayer.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            MapLegend()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.surface)
    }
}

// MARK: - Map components

struct MarkerDetailCard: View {
    let marker: IncidentMarker
    let onClose: () -> Void

    var body: some View {
        Card(padding: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: marker.icon)
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(marker.color)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(marker.title).font(.subheadline.weight(.semibold)).foregroundColor(Theme.textPrimary)
                    Text(marker.detail).font(.caption).foregroundColor(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Close details")
            }
            Button(action: openDirections) {
                ActionLabel(title: "Directions", icon: "car.fill")
            }
        }
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }

    /// Hands the marker to Apple Maps for turn-by-turn driving directions.
    private func openDirections() {
        let destination = MKMapItem(placemark: MKPlacemark(coordinate: marker.coordinate))
        destination.name = marker.title
        destination.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }
}

struct MapLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            LegendItem(symbol: "airplane.circle.fill", label: "drone", color: Theme.blue)
            LegendItem(symbol: "pause.circle.fill", label: "hovering", color: Theme.blue)
            LegendItem(symbol: "person.circle.fill", label: "victim", color: Theme.danger)
            LegendItem(symbol: "square.dashed", label: "zone", color: Theme.green)
        }
        .font(.caption)
    }
}

struct MapControlButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(Theme.blue)
                .frame(width: 50, height: 50)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border, lineWidth: 1))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        }
        .accessibilityLabel(label)
    }
}
