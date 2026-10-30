//
//  IncidentMap.swift
//  MercyDrones — live incident map
//
//  Everything map-related lives here: Zone A's coordinates, the markers built
//  from the fleet, the in-page map card and the full-screen map. Positions are
//  fixed prototype coordinates, but the map itself is the Google Maps SDK so
//  the same map works once the app is brought over to Android.
//
//  Responders can also drop category pins and draw boundaries on the
//  full-screen map. That data, its storage and its sync hook live in
//  MapAnnotations.swift.
//
//  Staying inside Google's free tier:
//  - Map loads through the native mobile SDK (iOS/Android) are unlimited and
//    free. Only the SDK is used here — no Directions, Geocoding, Places, Static
//    Maps or Street View calls, which are the metered ones.
//  - Directions open Google Maps through a plain Maps URL, which needs no key
//    and is not billed.
//  - Without an API key (or in SwiftUI previews, or before the GoogleMaps
//    package is added) the map falls back to an offline drawing that makes no
//    network calls at all.
//
//  Shared styling (Theme, Card, ActionLabel, LegendItem, MapGrid) comes from UI.swift.
//

import SwiftUI
import CoreLocation
#if canImport(GoogleMaps)
import GoogleMaps
#endif

// MARK: - Zone A data

/// Plain latitude/longitude pair. Kept free of MapKit and CoreLocation types so
/// the incident data can be shared with the Android build.
struct GeoPoint: Equatable, Codable {
    let latitude: Double
    let longitude: Double
}

/// Fixed prototype coordinates for Zone A (same area as the victim detections).
enum IncidentSite {
    static let center = GeoPoint(latitude: 34.0502, longitude: -118.2403)
    /// Roughly how much ground the default view covers, edge to edge.
    static let spanMeters = 900.0
    /// Google zoom level that shows about `spanMeters` across a phone-width map.
    static let zoom: Float = 15.8

    static let searchZone = [
        GeoPoint(latitude: 34.0519, longitude: -118.2429),
        GeoPoint(latitude: 34.0521, longitude: -118.2382),
        GeoPoint(latitude: 34.0487, longitude: -118.2376),
        GeoPoint(latitude: 34.0483, longitude: -118.2424)
    ]

    static let dronePositions = [
        "MD-01": GeoPoint(latitude: 34.0509, longitude: -118.2416),
        "MD-02": GeoPoint(latitude: 34.0493, longitude: -118.2389)
    ]
    static let hoveringDrones: Set<String> = ["MD-02"]

    private static let metersPerDegree = 111_320.0

    /// Flat projection around Zone A, used by the offline map.
    static func project(_ point: GeoPoint, into size: CGSize) -> CGPoint {
        let dx = (point.longitude - center.longitude) * metersPerDegree * cos(center.latitude * .pi / 180)
        let dy = (point.latitude - center.latitude) * metersPerDegree
        let scale = min(size.width, size.height) / spanMeters
        return CGPoint(x: size.width / 2 + dx * scale, y: size.height / 2 - dy * scale)
    }

    /// Inverse of `project`, for taps on the offline map.
    static func unproject(_ point: CGPoint, from size: CGSize) -> GeoPoint {
        let scale = min(size.width, size.height) / spanMeters
        let dx = (point.x - size.width / 2) / scale
        let dy = (size.height / 2 - point.y) / scale
        return GeoPoint(latitude: center.latitude + dy / metersPerDegree,
                        longitude: center.longitude + dx / (metersPerDegree * cos(center.latitude * .pi / 180)))
    }
}

struct Detection: Identifiable {
    let id: Int
    let title: String
    let coordinate: GeoPoint
    let confidence: Double

    var coords: String { String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude) }

    /// Shared by the Victims list and the map markers.
    static let zoneA = [
        Detection(id: 1, title: "Victim 01 · behind rubble",
                  coordinate: GeoPoint(latitude: 34.0501, longitude: -118.2402), confidence: 0.94),
        Detection(id: 2, title: "Victim 02 · street level",
                  coordinate: GeoPoint(latitude: 34.0498, longitude: -118.2410), confidence: 0.71),
        Detection(id: 3, title: "Possible · near vehicle",
                  coordinate: GeoPoint(latitude: 34.0507, longitude: -118.2395), confidence: 0.51)
    ]
}

struct IncidentMarker: Identifiable {
    enum Kind: Equatable { case drone, hoveringDrone, victim, hazard(PinCategory) }

    let id: String
    let kind: Kind
    let coordinate: GeoPoint
    let title: String
    let detail: String
    var shortName: String? = nil

    /// Short name drawn on the map, e.g. "Victim 01" instead of the full title.
    var label: String { shortName ?? title.components(separatedBy: " · ").first ?? title }

    /// Set for pins a responder dropped by hand.
    var category: PinCategory? {
        if case .hazard(let category) = kind { return category }
        return nil
    }

    var icon: String {
        switch kind {
        case .drone:         return "airplane"
        case .hoveringDrone: return "pause.fill"
        case .victim:        return "person.fill"
        case .hazard:        return "mappin"
        }
    }

    var color: Color {
        switch kind {
        case .drone, .hoveringDrone: return Theme.blue
        case .victim:                return Theme.danger
        case .hazard(let category):  return category.color
        }
    }

    /// Google Maps link for driving directions. Opens the Google Maps app when
    /// installed (iOS and Android), otherwise the browser. No key, no billing.
    var directionsURL: URL? {
        var components = URLComponents(string: "https://www.google.com/maps/dir/")
        components?.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: "\(coordinate.latitude),\(coordinate.longitude)"),
            URLQueryItem(name: "travelmode", value: "driving")
        ]
        return components?.url
    }
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
}

/// A request to move the map. Every request made with `to(_:)` is unique, so
/// tapping "Recenter" again still works after the responder has panned away.
struct MapFocus: Equatable {
    enum Target { case zoneA, userLocation }

    let target: Target
    private let id = UUID()

    private init(_ target: Target) { self.target = target }

    /// Where the map starts.
    static let initial = MapFocus(.zoneA)
    static func to(_ target: Target) -> MapFocus { MapFocus(target) }
}

// MARK: - Google Maps setup

enum GoogleMapsConfig {
    /// Comes from Info.plist (`GMSApiKey`), which is filled from
    /// GOOGLE_MAPS_API_KEY in the gitignored Secrets.xcconfig.
    static let apiKey: String? = {
        let key = (Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let key, !key.isEmpty, !key.hasPrefix("$(") else { return nil }
        return key
    }()

    /// True once the SDK has a key. Evaluated once, on first use.
    static let isAvailable: Bool = {
        #if canImport(GoogleMaps)
        let inPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        guard let apiKey, !inPreview else { return false }
        return GMSServices.provideAPIKey(apiKey)
        #else
        return false
        #endif
    }()

    /// Call once at launch, before any map is shown.
    static func configure() { _ = isAvailable }
}

// MARK: - Map

/// The map itself, shared by the in-page card and the full-screen view.
struct IncidentMap: View {
    let markers: [IncidentMarker]
    var boundaries: [IncidentBoundary] = []
    /// Corners of a boundary still being drawn.
    var draftBoundary: [GeoPoint] = []
    let layer: MapLayer
    @Binding var focus: MapFocus
    @Binding var selection: String?
    var interactive = true
    /// When set, every tap (markers included) reports its coordinate here
    /// instead of selecting. Used while dropping a pin or drawing a boundary.
    var onMapTap: ((GeoPoint) -> Void)? = nil

    var body: some View {
        #if canImport(GoogleMaps)
        if GoogleMapsConfig.isAvailable {
            GoogleIncidentMap(markers: markers, boundaries: boundaries, draftBoundary: draftBoundary,
                              layer: layer, focus: $focus, selection: $selection,
                              interactive: interactive, onMapTap: onMapTap)
        } else {
            offlineMap
        }
        #else
        offlineMap
        #endif
    }

    private var offlineMap: some View {
        OfflineIncidentMap(markers: markers, boundaries: boundaries, draftBoundary: draftBoundary,
                           selection: $selection, interactive: interactive, onMapTap: onMapTap)
    }
}

#if canImport(GoogleMaps)
private extension GeoPoint {
    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    var clCoordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

private extension MapLayer {
    var mapType: GMSMapViewType {
        switch self {
        case .standard:  return .normal
        case .satellite: return .satellite
        case .hybrid:    return .hybrid
        }
    }
}

/// GMSMapView wrapped for SwiftUI.
private struct GoogleIncidentMap: UIViewRepresentable {
    let markers: [IncidentMarker]
    let boundaries: [IncidentBoundary]
    let draftBoundary: [GeoPoint]
    let layer: MapLayer
    @Binding var focus: MapFocus
    @Binding var selection: String?
    let interactive: Bool
    let onMapTap: ((GeoPoint) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeUIView(context: Context) -> GMSMapView {
        let options = GMSMapViewOptions()
        options.camera = GMSCameraPosition(target: IncidentSite.center.clCoordinate, zoom: IncidentSite.zoom)
        let map = GMSMapView(options: options)
        map.delegate = context.coordinator
        map.isMyLocationEnabled = interactive
        map.settings.setAllGesturesEnabled(interactive)
        map.settings.consumesGesturesInView = interactive
        map.settings.compassButton = interactive
        Self.drawSearchZone(on: map)
        context.coordinator.appliedFocus = focus
        return map
    }

    func updateUIView(_ map: GMSMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.selection = $selection
        coordinator.onMapTap = onMapTap
        if map.mapType != layer.mapType { map.mapType = layer.mapType }
        coordinator.sync(markers, selected: selection, on: map)
        coordinator.syncBoundaries(boundaries, selected: selection, on: map)
        coordinator.syncDraft(draftBoundary, on: map)

        if focus != coordinator.appliedFocus {
            coordinator.appliedFocus = focus
            map.animate(to: camera(for: focus.target, on: map))
        }
    }

    private func camera(for target: MapFocus.Target, on map: GMSMapView) -> GMSCameraPosition {
        if target == .userLocation, let here = map.myLocation?.coordinate {
            return GMSCameraPosition(target: here, zoom: max(map.camera.zoom, IncidentSite.zoom))
        }
        return GMSCameraPosition(target: IncidentSite.center.clCoordinate, zoom: IncidentSite.zoom)
    }

    /// Light green fill plus a dashed outline, matching the legend.
    private static func drawSearchZone(on map: GMSMapView) {
        let green = UIColor(Theme.green)
        let path = GMSMutablePath()
        IncidentSite.searchZone.forEach { path.add($0.clCoordinate) }

        let fill = GMSPolygon(path: path)
        fill.fillColor = green.withAlphaComponent(0.12)
        fill.strokeWidth = 0
        fill.map = map

        if let first = IncidentSite.searchZone.first { path.add(first.clCoordinate) }
        let outline = GMSPolyline(path: path)
        outline.strokeWidth = 2
        outline.spans = GMSStyleSpans(path,
                                      [GMSStrokeStyle.solidColor(green), GMSStrokeStyle.solidColor(.clear)],
                                      [25, 15],
                                      .rhumb)
        outline.map = map
    }

    final class Coordinator: NSObject, GMSMapViewDelegate {
        var selection: Binding<String?>
        var appliedFocus: MapFocus?
        var onMapTap: ((GeoPoint) -> Void)?
        private var pins: [String: GMSMarker] = [:]
        private var pinState: [String: String] = [:]
        private var shapes: [UUID: GMSPolygon] = [:]
        private var shapeState: [UUID: String] = [:]
        private var draftLine: GMSPolyline?
        private var draftCorners: [GMSMarker] = []
        private var appliedDraft: [GeoPoint] = []

        init(selection: Binding<String?>) { self.selection = selection }

        /// Adds, moves and removes pins so they match `markers`.
        func sync(_ markers: [IncidentMarker], selected: String?, on map: GMSMapView) {
            let ids = Set(markers.map(\.id))
            for (id, pin) in pins where !ids.contains(id) {
                pin.map = nil
                pins[id] = nil
                pinState[id] = nil
            }

            for marker in markers {
                let pin = pins[marker.id] ?? GMSMarker()
                pin.position = marker.coordinate.clCoordinate
                pin.userData = marker.id
                pin.title = marker.title
                pin.snippet = marker.detail
                pin.accessibilityLabel = "\(marker.title), \(marker.detail)"

                // Only redraw the image when its label, kind or selection changed.
                let isSelected = marker.id == selected
                let state = "\(marker.label)|\(marker.kind)|\(isSelected)"
                if pinState[marker.id] != state {
                    let (image, anchor) = PinImage.render(marker, selected: isSelected)
                    pin.icon = image
                    pin.groundAnchor = anchor
                    pin.zIndex = isSelected ? 3 : 2
                    pinState[marker.id] = state
                }

                if pin.map == nil { pin.map = map }
                pins[marker.id] = pin
            }
        }

        /// Adds, reshapes and removes boundary polygons so they match `boundaries`.
        func syncBoundaries(_ boundaries: [IncidentBoundary], selected: String?, on map: GMSMapView) {
            let ids = Set(boundaries.map(\.id))
            for (id, shape) in shapes where !ids.contains(id) {
                shape.map = nil
                shapes[id] = nil
                shapeState[id] = nil
            }

            let tappable = onMapTap == nil
            for boundary in boundaries {
                let shape = shapes[boundary.id] ?? GMSPolygon()
                let isSelected = boundary.selectionID == selected
                let state = "\(boundary)|\(isSelected)|\(tappable)"
                if shapeState[boundary.id] != state {
                    let path = GMSMutablePath()
                    boundary.points.forEach { path.add($0.clCoordinate) }
                    let color = UIColor(boundary.color)
                    shape.path = path
                    shape.fillColor = color.withAlphaComponent(0.25)
                    shape.strokeColor = color
                    shape.strokeWidth = isSelected ? 4 : 2
                    shape.title = boundary.name
                    shape.userData = boundary.selectionID
                    // While pinning or drawing, taps on a boundary go to the map instead.
                    shape.isTappable = tappable
                    shape.zIndex = 1
                    shapeState[boundary.id] = state
                }

                if shape.map == nil { shape.map = map }
                shapes[boundary.id] = shape
            }
        }

        /// Redraws the outline and corner dots of the boundary being drawn.
        func syncDraft(_ points: [GeoPoint], on map: GMSMapView) {
            guard points != appliedDraft else { return }
            appliedDraft = points
            draftLine?.map = nil
            draftLine = nil
            draftCorners.forEach { $0.map = nil }
            draftCorners = []
            guard !points.isEmpty else { return }

            let path = GMSMutablePath()
            points.forEach { path.add($0.clCoordinate) }
            if points.count >= 3, let first = points.first { path.add(first.clCoordinate) }
            let line = GMSPolyline(path: path)
            line.strokeWidth = 3
            line.strokeColor = UIColor(Theme.blue)
            line.zIndex = 4
            line.map = map
            draftLine = line

            draftCorners = points.map { point in
                let corner = GMSMarker(position: point.clCoordinate)
                corner.icon = PinImage.corner
                corner.groundAnchor = CGPoint(x: 0.5, y: 0.5)
                corner.isTappable = false
                corner.zIndex = 5
                corner.map = map
                return corner
            }
        }

        func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            if let onMapTap {
                onMapTap(GeoPoint(marker.position))
            } else {
                selection.wrappedValue = marker.userData as? String
            }
            return true  // We show MarkerDetailCard instead of Google's info window.
        }

        func mapView(_ mapView: GMSMapView, didTap overlay: GMSOverlay) {
            selection.wrappedValue = overlay.userData as? String
        }

        func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            if let onMapTap {
                onMapTap(GeoPoint(coordinate))
            } else {
                selection.wrappedValue = nil
            }
        }
    }
}

/// Draws a round pin with an SF Symbol and the marker's short name under it,
/// so Google pins look like the legend. Responder pins use their category logo
/// and get a pointer under the badge.
private enum PinImage {
    static func render(_ marker: IncidentMarker, selected: Bool) -> (UIImage, CGPoint) {
        let circleSize: CGFloat = selected ? 40 : 32
        let tail: CGFloat = marker.category == nil ? 0 : 8
        let font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        let label = NSAttributedString(string: marker.label, attributes: [
            .font: font,
            .foregroundColor: UIColor(Theme.textPrimary)
        ])
        let labelSize = label.size()
        let capsule = CGSize(width: labelSize.width + 10, height: labelSize.height + 4)
        let size = CGSize(width: max(circleSize, capsule.width), height: circleSize + tail + 3 + capsule.height)

        let image = UIGraphicsImageRenderer(size: size).image { _ in
            let circle = CGRect(x: (size.width - circleSize) / 2, y: 0, width: circleSize, height: circleSize)

            if let category = marker.category {
                let pointer = UIBezierPath()
                pointer.move(to: CGPoint(x: circle.midX - circleSize * 0.25, y: circle.maxY - circleSize * 0.2))
                pointer.addLine(to: CGPoint(x: circle.midX, y: circle.maxY + tail))
                pointer.addLine(to: CGPoint(x: circle.midX + circleSize * 0.25, y: circle.maxY - circleSize * 0.2))
                pointer.close()
                UIColor.white.setFill()
                pointer.fill()
                HazardLogo.draw(category, in: circle)
            } else {
                UIColor.white.setFill()
                UIBezierPath(ovalIn: circle).fill()
                UIColor(marker.color).setFill()
                UIBezierPath(ovalIn: circle.insetBy(dx: 2.5, dy: 2.5)).fill()

                let config = UIImage.SymbolConfiguration(pointSize: circleSize * 0.4, weight: .bold)
                if let symbol = UIImage(systemName: marker.icon, withConfiguration: config)?
                    .withTintColor(.white, renderingMode: .alwaysOriginal) {
                    symbol.draw(at: CGPoint(x: circle.midX - symbol.size.width / 2,
                                            y: circle.midY - symbol.size.height / 2))
                }
            }

            let pill = CGRect(x: (size.width - capsule.width) / 2, y: circleSize + tail + 3,
                              width: capsule.width, height: capsule.height)
            UIColor(Theme.surface).withAlphaComponent(0.9).setFill()
            UIBezierPath(roundedRect: pill, cornerRadius: pill.height / 2).fill()
            label.draw(at: CGPoint(x: pill.minX + 5, y: pill.minY + 2))
        }

        // Anchor on the circle's centre (or the pointer's tip) so the pin sits on the coordinate.
        let anchorY = marker.category == nil ? circleSize / 2 : circleSize + tail
        return (image, CGPoint(x: 0.5, y: anchorY / size.height))
    }

    /// Dot marking a corner of the boundary being drawn.
    static let corner: UIImage = {
        let rect = CGRect(x: 0, y: 0, width: 16, height: 16)
        return UIGraphicsImageRenderer(size: rect.size).image { _ in
            UIColor(Theme.blue).setFill()
            UIBezierPath(ovalIn: rect).fill()
            UIColor.white.setFill()
            UIBezierPath(ovalIn: rect.insetBy(dx: 4, dy: 4)).fill()
        }
    }()
}
#endif

/// Network-free stand-in used when there's no Google Maps key (and in
/// previews). Same zone, pins and selection, drawn on the placeholder grid.
private struct OfflineIncidentMap: View {
    let markers: [IncidentMarker]
    let boundaries: [IncidentBoundary]
    let draftBoundary: [GeoPoint]
    @Binding var selection: String?
    let interactive: Bool
    let onMapTap: ((GeoPoint) -> Void)?

    var body: some View {
        GeometryReader { geo in
            let zone = IncidentSite.searchZone.map { IncidentSite.project($0, into: geo.size) }
            // While pinning or drawing, taps fall through to the map underneath.
            let selectable = onMapTap == nil
            ZStack {
                Theme.surfaceAlt
                    .onTapGesture(coordinateSpace: .local) { location in
                        if let onMapTap {
                            if interactive { onMapTap(IncidentSite.unproject(location, from: geo.size)) }
                        } else {
                            selection = nil
                        }
                    }
                MapGrid().stroke(Theme.border, lineWidth: 0.6)
                    .allowsHitTesting(false)

                Path { path in
                    path.addLines(zone)
                    path.closeSubpath()
                }
                .fill(Theme.green.opacity(0.12))
                .allowsHitTesting(false)
                Path { path in
                    path.addLines(zone)
                    path.closeSubpath()
                }
                .stroke(Theme.green, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                .allowsHitTesting(false)

                ForEach(boundaries) { boundary in
                    let shape = PolygonShape(points: boundary.points.map { IncidentSite.project($0, into: geo.size) })
                    let isSelected = boundary.selectionID == selection
                    shape.fill(boundary.color.opacity(0.25))
                        .overlay(shape.stroke(boundary.color, lineWidth: isSelected ? 4 : 2))
                        .contentShape(shape)
                        .onTapGesture { if interactive { selection = boundary.selectionID } }
                        .allowsHitTesting(selectable)
                        .accessibilityLabel("\(boundary.name) boundary")
                        .accessibilityAddTraits(.isButton)
                }

                if !draftBoundary.isEmpty {
                    let corners = draftBoundary.map { IncidentSite.project($0, into: geo.size) }
                    PolygonShape(points: corners, closed: corners.count >= 3)
                        .stroke(Theme.blue, style: StrokeStyle(lineWidth: 2.5, dash: [6, 4]))
                        .allowsHitTesting(false)
                    ForEach(corners.indices, id: \.self) { i in
                        Circle()
                            .fill(Color.white)
                            .overlay(Circle().stroke(Theme.blue, lineWidth: 4))
                            .frame(width: 16, height: 16)
                            .position(corners[i])
                            .allowsHitTesting(false)
                    }
                }

                ForEach(markers) { marker in
                    OfflinePin(marker: marker, selected: marker.id == selection)
                        .onTapGesture { if interactive { selection = marker.id } }
                        .allowsHitTesting(selectable)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(marker.title), \(marker.detail)")
                        .accessibilityAddTraits(.isButton)
                        .position(IncidentSite.project(marker.coordinate, into: geo.size))
                }
            }
        }
        .overlay(alignment: .bottomLeading) {
            if interactive {
                Text("Offline map · add a Google Maps key for live tiles")
                    .font(.caption2)
                    .foregroundColor(Theme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(10)
            }
        }
    }
}

private struct PolygonShape: Shape {
    let points: [CGPoint]
    var closed = true

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.addLines(points)
            if closed { path.closeSubpath() }
        }
    }
}

private struct OfflinePin: View {
    let marker: IncidentMarker
    let selected: Bool

    var body: some View {
        if let category = marker.category {
            let size: CGFloat = selected ? 40 : 32
            VStack(spacing: -2) {
                HazardBadge(category: category, diameter: size)
                PinPointer()
                    .fill(Color.white)
                    .frame(width: size * 0.5, height: 10)
            }
            .overlay(alignment: .bottom) {
                nameTag.fixedSize().alignmentGuide(.bottom) { $0[.top] - 3 }
            }
            // Keep the pointer's tip on the coordinate.
            .offset(y: -(size + 8) / 2)
        } else {
            VStack(spacing: 3) {
                Image(systemName: marker.icon)
                    .font(.system(size: selected ? 16 : 13, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: selected ? 40 : 32, height: selected ? 40 : 32)
                    .background(marker.color)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white, lineWidth: 2.5))
                nameTag
            }
            // Keep the circle, not the whole stack, centred on the coordinate.
            .offset(y: 10)
        }
    }

    private var nameTag: some View {
        Text(marker.label)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Theme.textPrimary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Theme.surface.opacity(0.9), in: Capsule())
    }
}

/// Downward triangle under a responder pin's badge.
private struct PinPointer: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.closeSubpath()
        }
    }
}

/// In-page map for the Overview. It stays still so the page scrolls normally;
/// tapping it opens the full-screen map for panning and zooming.
struct IncidentMapCard: View {
    @EnvironmentObject private var store: PrototypeStore
    @EnvironmentObject private var annotations: MapAnnotationStore
    @AppStorage("mapLayer") private var layer: MapLayer = .standard
    @State private var expanded = false

    var body: some View {
        Button { expanded = true } label: {
            IncidentMap(markers: store.incidentMarkers + annotations.markers,
                        boundaries: annotations.boundaries,
                        layer: layer,
                        focus: .constant(.initial),
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
                .environmentObject(annotations)
                .tint(Theme.blue)
        }
    }
}

/// What a tap on the full-screen map does.
private enum MapEditMode {
    case browse, droppingPin, drawingBoundary
}

/// Map coordinate waiting for a category in `NewPinSheet`.
private struct PinDraft: Identifiable {
    let id = UUID()
    let coordinate: GeoPoint
}

/// Full-screen, fully interactive map so responders can see the wider area,
/// find themselves, get directions to a victim or drone, and mark up the
/// scene with pins and boundaries.
struct FullScreenMapView: View {
    @EnvironmentObject private var store: PrototypeStore
    @EnvironmentObject private var annotations: MapAnnotationStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("mapLayer") private var layer: MapLayer = .standard
    @State private var focus = MapFocus.initial
    @State private var selection: String?
    @State private var locationManager = CLLocationManager()
    @State private var editMode = MapEditMode.browse
    @State private var draftCorners: [GeoPoint] = []
    @State private var newPin: PinDraft?
    @State private var choosingCover = false

    private var markers: [IncidentMarker] { store.incidentMarkers + annotations.markers }

    private var selectedMarker: IncidentMarker? {
        markers.first { $0.id == selection }
    }

    private var selectedPin: HazardPin? {
        annotations.pins.first { $0.selectionID == selection }
    }

    private var selectedBoundary: IncidentBoundary? {
        annotations.boundaries.first { $0.selectionID == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            IncidentMap(markers: markers,
                        boundaries: annotations.boundaries,
                        draftBoundary: draftCorners,
                        layer: layer,
                        focus: $focus,
                        selection: $selection,
                        onMapTap: editMode == .browse ? nil : handleMapTap)
                .safeAreaInset(edge: .bottom) {
                    bottomBar.padding(16)
                }
        }
        .background(Theme.surface.ignoresSafeArea())
        .onAppear {
            if locationManager.authorizationStatus == .notDetermined {
                locationManager.requestWhenInUseAuthorization()
            }
        }
        .task { await annotations.refresh() }
        .sheet(item: $newPin) { draft in
            NewPinSheet(coordinate: draft.coordinate) { category, note in
                let pin = annotations.addPin(category, note: note, at: draft.coordinate)
                editMode = .browse
                selection = pin.selectionID
            }
        }
        .sheet(isPresented: $choosingCover) {
            BoundaryCoverSheet(defaultName: "Boundary \(annotations.boundaries.count + 1)",
                               cornerCount: draftCorners.count) { name, colorHex in
                let boundary = annotations.addBoundary(name: name, corners: draftCorners, colorHex: colorHex)
                draftCorners = []
                editMode = .browse
                selection = boundary.selectionID
            }
        }
    }

    private func handleMapTap(_ point: GeoPoint) {
        switch editMode {
        case .browse:          selection = nil
        case .droppingPin:     newPin = PinDraft(coordinate: point)
        case .drawingBoundary: draftCorners.append(point)
        }
    }

    /// Only responder pins can be deleted, not drones or victims.
    private var deleteSelectedPin: (() -> Void)? {
        guard let pin = selectedPin else { return nil }
        return {
            annotations.removePin(pin.id)
            selection = nil
        }
    }

    private func begin(_ mode: MapEditMode) {
        selection = nil
        draftCorners = []
        editMode = mode
    }

    @ViewBuilder private var bottomBar: some View {
        switch editMode {
        case .browse:
            HStack(alignment: .bottom, spacing: 12) {
                if let marker = selectedMarker {
                    MarkerDetailCard(marker: marker, onDelete: deleteSelectedPin) {
                        selection = nil
                    }
                } else if let boundary = selectedBoundary {
                    BoundaryDetailCard(boundary: boundary,
                                       onRecolor: { annotations.recolorBoundary(boundary.id, to: $0) },
                                       onDelete: { annotations.removeBoundary(boundary.id); selection = nil },
                                       onClose: { selection = nil })
                } else {
                    Spacer()
                }
                VStack(spacing: 10) {
                    Menu {
                        Button { begin(.droppingPin) } label: {
                            Label("Drop pin", systemImage: "mappin.and.ellipse")
                        }
                        Button { begin(.drawingBoundary) } label: {
                            Label("Draw boundary", systemImage: "hexagon")
                        }
                    } label: {
                        MapControlLabel(icon: "plus")
                    }
                    .accessibilityLabel("Add to map")
                    MapControlButton(icon: "location.fill", label: "Show my location") {
                        focus = .to(.userLocation)
                    }
                    MapControlButton(icon: "scope", label: "Recenter on Zone A") {
                        focus = .to(.zoneA)
                    }
                }
            }
        case .droppingPin:
            MapEditBanner(icon: "mappin.and.ellipse",
                          title: "Drop a pin",
                          message: "Tap the map where the pin goes.") {
                Button { editMode = .browse } label: { ActionLabel(title: "Cancel", style: .secondary) }
            }
        case .drawingBoundary:
            MapEditBanner(icon: "hexagon",
                          title: "Draw a boundary",
                          message: draftCorners.isEmpty
                            ? "Tap the map to place each corner."
                            : "\(draftCorners.count) corner\(draftCorners.count == 1 ? "" : "s") · tap to add more") {
                HStack(spacing: 10) {
                    Button { draftCorners.removeLast() } label: {
                        ActionLabel(title: "Undo", icon: "arrow.uturn.backward", style: .secondary)
                    }
                    .disabled(draftCorners.isEmpty)
                    Button { begin(.browse) } label: { ActionLabel(title: "Cancel", style: .secondary) }
                    Button { choosingCover = true } label: { ActionLabel(title: "Next", style: .green) }
                        .disabled(draftCorners.count < 3)
                        .opacity(draftCorners.count < 3 ? 0.45 : 1)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Zone A · live").font(.headline).foregroundColor(Theme.textPrimary)
                    Text("tap a marker for details · + to pin or draw a boundary")
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
    /// Set for responder pins, which can be removed.
    var onDelete: (() -> Void)? = nil
    let onClose: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var confirmingDelete = false

    var body: some View {
        Card(padding: 12) {
            HStack(alignment: .top, spacing: 12) {
                if let category = marker.category {
                    HazardBadge(category: category, diameter: 36)
                } else {
                    Image(systemName: marker.icon)
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(marker.color)
                        .clipShape(Circle())
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(marker.title).font(.subheadline.weight(.semibold)).foregroundColor(Theme.textPrimary)
                    Text(marker.detail).font(.caption).foregroundColor(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                if onDelete != nil {
                    DeleteButton(label: "Delete pin") { confirmingDelete = true }
                }
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundColor(Theme.textSecondary)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Close details")
            }
            Button {
                if let url = marker.directionsURL { openURL(url) }
            } label: {
                ActionLabel(title: "Directions", icon: "car.fill")
            }
        }
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .confirmationDialog("Delete this pin?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete pin", role: .destructive) { onDelete?() }
        }
    }
}

/// Instructions and actions shown in place of the map controls while dropping
/// a pin or drawing a boundary.
private struct MapEditBanner<Actions: View>: View {
    let icon: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        Card(padding: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Theme.blue)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundColor(Theme.textPrimary)
                    Text(message).font(.caption).foregroundColor(Theme.textSecondary)
                }
            }
            actions
        }
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }
}

struct MapLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                LegendItem(symbol: "airplane.circle.fill", label: "drone", color: Theme.blue)
                LegendItem(symbol: "pause.circle.fill", label: "hovering", color: Theme.blue)
                LegendItem(symbol: "person.circle.fill", label: "victim", color: Theme.danger)
                LegendItem(symbol: "square.dashed", label: "zone", color: Theme.green)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(PinCategory.allCases) { category in
                        HStack(spacing: 4) {
                            HazardBadge(category: category, diameter: 18)
                            Text(category.shortName.lowercased()).foregroundColor(Theme.textSecondary)
                        }
                    }
                }
            }
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
            MapControlLabel(icon: icon)
        }
        .accessibilityLabel(label)
    }
}

/// The square look of the map's floating controls, for buttons and menus alike.
struct MapControlLabel: View {
    let icon: String

    var body: some View {
        Image(systemName: icon)
            .font(.title3)
            .foregroundColor(Theme.blue)
            .frame(width: 50, height: 50)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.border, lineWidth: 1))
            .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }
}
