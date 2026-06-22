import CoreLocation
import MapKit
import SwiftUI

struct RouteTrackingView: View {
    @ObservedObject var locationManager: LocationManager
    @EnvironmentObject private var areaBoundariesStore: AreaBoundariesStore
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var showEndRouteNaming = false
    @State private var showPausedRouteNaming = false
    @State private var routeName = ""
    @State private var showNewRouteConfirmation = false
    @AppStorage("routeHistoryWasOpen") private var routeHistoryWasOpen = false
    @AppStorage("pendingRouteHistoryRestore") private var pendingRouteHistoryRestore = false
    @AppStorage("mapDisplayStyle") private var mapDisplayStyle = MapDisplayStyle.illustrated.rawValue
    @AppStorage("activeOverlayBoundaryId") private var activeOverlayBoundaryIdRaw = ""
    @State private var showRouteHistory = false
    @State private var showAreaBoundaries = false
    @State private var baselineSegmentMarkerIDs: Set<UUID> = []
    @State private var pendingMarkerDrops: [PendingMarkerDrop] = []
    @Environment(\.openURL) private var openURL

    private var overlayBoundaryId: UUID? {
        UUID(uuidString: activeOverlayBoundaryIdRaw)
    }

    private var overlayBoundaryIdBinding: Binding<UUID?> {
        Binding(
            get: { UUID(uuidString: activeOverlayBoundaryIdRaw) },
            set: { activeOverlayBoundaryIdRaw = $0?.uuidString ?? "" }
        )
    }

    var body: some View {
        map
            .safeAreaInset(edge: .bottom, spacing: 0) {
                controlPanel
            }
            .overlay(alignment: .top) {
                if !locationManager.isViewingActiveRoute, let route = locationManager.displayedRoute {
                    viewingBanner(for: route)
                }
            }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        mapDisplayStyle = MapDisplayStyle.illustrated.rawValue
                    } label: {
                        Label("Illustrated", systemImage: "map")
                    }

                    Button {
                        mapDisplayStyle = MapDisplayStyle.satellite.rawValue
                    } label: {
                        Label("Satellite", systemImage: "globe.americas.fill")
                    }
                } label: {
                    Image(systemName: selectedMapDisplayStyle.toggleIcon)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showAreaBoundaries = true
                } label: {
                    Image(systemName: overlayBoundaryId == nil ? "square.dashed" : "square.dashed.inset.filled")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showRouteHistory = true
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
            }
        }
        .sheet(isPresented: $showRouteHistory) {
            RouteHistoryView(locationManager: locationManager)
        }
        .sheet(isPresented: $showAreaBoundaries) {
            AreaBoundariesListSheet(
                overlayBoundaryId: overlayBoundaryIdBinding,
                onFocusBoundary: { boundary in
                    cameraPosition = .region(boundary.coordinateRegion)
                }
            )
        }
        .onChange(of: activeOverlayBoundaryIdRaw) { _, _ in
            syncActiveBoundaryOverlay()
            if let id = overlayBoundaryId,
               let boundary = areaBoundariesStore.boundary(id: id) {
                cameraPosition = .region(boundary.coordinateRegion)
            }
        }
        .onAppear {
            syncSegmentMarkerBaseline()
            presentPausedRouteNamingIfNeeded()
            restoreRouteHistoryIfNeeded()
            syncActiveBoundaryOverlay()
        }
        .onChange(of: locationManager.activeRouteId) { _, _ in
            pendingMarkerDrops = []
            syncSegmentMarkerBaseline()
        }
        .onChange(of: locationManager.segmentMarkers.map(\.id)) { _, _ in
            queueSegmentMarkerDropAnimations()
        }
        .onChange(of: locationManager.needsPausedRouteNaming) { _, needed in
            if needed {
                presentPausedRouteNamingIfNeeded()
            }
        }
        .onChange(of: pendingRouteHistoryRestore) { _, _ in
            restoreRouteHistoryIfNeeded()
        }
        .onChange(of: showRouteHistory) { _, isOpen in
            routeHistoryWasOpen = isOpen
        }
        .sheet(isPresented: $showEndRouteNaming) {
            EndRouteNamingSheet(
                mode: .endRoute,
                routeName: $routeName,
                locationManager: locationManager,
                onEnd: { name, method, neighborhoodType, highlighterColor in
                    locationManager.stopTracking(
                        name: name,
                        method: method,
                        neighborhoodType: neighborhoodType,
                        highlighterColor: highlighterColor
                    )
                    routeName = ""
                    showEndRouteNaming = false
                    haptic(.rigid)
                },
                onResume: {
                    routeName = ""
                    showEndRouteNaming = false
                }
            )
        }
        .sheet(isPresented: $showPausedRouteNaming) {
            EndRouteNamingSheet(
                mode: .pausedRouteOnReopen,
                routeName: $routeName,
                locationManager: locationManager,
                onEnd: { name, method, neighborhoodType, highlighterColor in
                    if locationManager.saveActiveRouteDetails(
                        name: name,
                        method: method,
                        neighborhoodType: neighborhoodType,
                        highlighterColor: highlighterColor
                    ) {
                        routeName = ""
                        showPausedRouteNaming = false
                        if routeHistoryWasOpen {
                            pendingRouteHistoryRestore = true
                        }
                        restoreRouteHistoryIfNeeded()
                    }
                },
                onResume: {}
            )
        }
        .alert("Start New Route?", isPresented: $showNewRouteConfirmation) {
            Button("Start New Route", role: .destructive) {
                locationManager.requestNewRoute()
                haptic(.medium)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your current route will be saved with its end time, then a new route will begin.")
        }
    }

    private func viewingBanner(for route: RouteRecord) -> some View {
        VStack(spacing: 8) {
            Text("Viewing Past Route")
                .font(.subheadline)
                .fontWeight(.semibold)

            if let name = route.trimmedName {
                Text(name)
                    .font(.caption)
                    .fontWeight(.semibold)

                if let method = route.trimmedMethod {
                    Text(method)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let neighborhoodType = route.trimmedNeighborhoodType {
                    Text(neighborhoodType)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(RouteDateFormatting.routeTimeRange(
                    startedAt: route.startedAt,
                    endedAt: route.endedAt
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text(route.displayTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if locationManager.activeRouteId != nil {
                Button("Back to Current Route") {
                    locationManager.returnToActiveRoute()
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private var map: some View {
        MapReader { proxy in
            ZStack {
                mapLayer

                ForEach(pendingMarkerDrops) { pending in
                    if let targetPoint = proxy.convert(pending.coordinate, to: .local) {
                        SegmentMarkerDropOverlay(
                            label: pending.label,
                            targetPoint: targetPoint
                        ) {
                            completeMarkerDrop(id: pending.id)
                        }
                    } else {
                        Color.clear
                            .onAppear {
                                completeMarkerDrop(id: pending.id)
                            }
                    }
                }
            }
        }
    }

    private var mapLayer: some View {
        Map(position: $cameraPosition) {
            if locationManager.isLocationAuthorized && locationManager.isViewingActiveRoute {
                UserAnnotation()
            }

            ForEach(locationManager.flyerDrops) { drop in
                Annotation("", coordinate: drop.coordinate, anchor: .center) {
                    Circle()
                        .fill(.orange)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }

            ForEach(locationManager.segmentMarkers) { marker in
                if !isMarkerPendingDrop(marker.id) {
                    Annotation("", coordinate: marker.coordinate, anchor: .bottom) {
                        RouteSegmentMarkerPin(label: marker.label)
                    }
                }
            }

            if locationManager.routeCoordinates.count >= 2 {
                MapPolyline(coordinates: locationManager.routeCoordinates)
                    .stroke(.blue, lineWidth: 4)
            }

            if let overlayBoundary = overlayBoundary {
                OutsideBoundaryRing(coordinates: overlayBoundary.coordinates)
            }
        }
        .mapControls {
            if locationManager.isLocationAuthorized && locationManager.isViewingActiveRoute {
                MapUserLocationButton()
            }
            MapCompass()
        }
        .mapStyle(selectedMapDisplayStyle.mapStyle)
    }

    private var selectedMapDisplayStyle: MapDisplayStyle {
        MapDisplayStyle(rawValue: mapDisplayStyle) ?? .illustrated
    }

    private var overlayBoundary: AreaBoundary? {
        guard let overlayBoundaryId else { return nil }
        return areaBoundariesStore.boundary(id: overlayBoundaryId)
    }

    @ViewBuilder
    private var controlPanel: some View {
        VStack(spacing: 16) {
            if let statusMessage = locationManager.statusMessage {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let route = locationManager.displayedRoute, locationManager.isViewingActiveRoute {
                routeTimestampLabel(for: route)
            }

            if locationManager.isTracking && locationManager.isViewingActiveRoute {
                statsRow

                Button {
                    locationManager.recordFlyerDrop()
                    haptic(.medium)
                } label: {
                    Text("+1 Flyer")
                        .font(.title)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!locationManager.canRecordFlyerDrop)

                Button {
                    locationManager.removeLastFlyerDrop()
                    haptic(.light)
                } label: {
                    Text("-1 Flyer")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!locationManager.canRemoveLastFlyerDrop)

                Button("End Route", role: .destructive) {
                    routeName = ""
                    showEndRouteNaming = true
                }
                .buttonStyle(.bordered)
            } else if locationManager.isLocationDenied
                        || !CLLocationManager.locationServicesEnabled() {
                ContentUnavailableView {
                    Label("Location Access Needed", systemImage: "location.slash")
                } description: {
                    Text("Flyer Counter needs your location to draw your route and place flyer pins on the map.")
                }
                .frame(maxWidth: .infinity)

                Button("Open Settings") {
                    openURL(URL(string: UIApplication.openSettingsURLString)!)
                }
                .buttonStyle(.borderedProminent)
            } else if locationManager.isViewingActiveRoute
                        && locationManager.hasRouteData
                        && !locationManager.needsPausedRouteNaming {
                statsRow

                Button {
                    locationManager.requestContinueRoute()
                    haptic(.medium)
                } label: {
                    Text("Continue Route")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 72)
                }
                .buttonStyle(.borderedProminent)

                Button("New Route", role: .destructive) {
                    showNewRouteConfirmation = true
                }
                .buttonStyle(.bordered)
            } else if locationManager.isViewingActiveRoute {
                Button {
                    locationManager.requestNewRoute()
                    haptic(.medium)
                } label: {
                    Text("Start Route")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 72)
                }
                .buttonStyle(.borderedProminent)
            } else if let route = locationManager.displayedRoute {
                statsRow
                routeTimestampLabel(for: route)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private func routeTimestampLabel(for route: RouteRecord) -> some View {
        VStack(spacing: 4) {
            if let name = route.trimmedName {
                Text(name)
                    .font(.footnote)
                    .fontWeight(.semibold)
            }

            if let method = route.trimmedMethod {
                Text(method)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let neighborhoodType = route.trimmedNeighborhoodType {
                Text(neighborhoodType)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text(RouteDateFormatting.routeTimeRange(
                startedAt: route.startedAt,
                endedAt: route.endedAt
            ))
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            statItem(title: "Flyers", value: "\(locationManager.flyerCount)")

            if let elapsedTimeState {
                elapsedTimeColumn(for: elapsedTimeState)
            }

            statItem(title: "Distance", value: formattedDistance)
        }
        .frame(maxWidth: .infinity)
    }

    private var elapsedTimeState: ElapsedTimeState? {
        guard locationManager.isViewingActiveRoute,
              let route = locationManager.displayedRoute else { return nil }

        if locationManager.isTracking {
            return .live
        }

        guard let duration = route.frozenRecordingElapsedDuration else { return nil }
        return .frozen(duration)
    }

    private enum ElapsedTimeState {
        case live
        case frozen(TimeInterval)
    }

    @ViewBuilder
    private func elapsedTimeColumn(for state: ElapsedTimeState) -> some View {
        switch state {
        case .live:
            LiveRecordingElapsedView(locationManager: locationManager)
        case .frozen(let duration):
            statItem(title: "Elapsed", value: RouteDateFormatting.formatDuration(duration))
        }
    }

    private func statItem(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var formattedDistance: String {
        Measurement(value: locationManager.distanceWalked, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    private func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    private func restoreRouteHistoryIfNeeded() {
        guard !locationManager.needsPausedRouteNaming else { return }
        guard routeHistoryWasOpen || pendingRouteHistoryRestore else { return }

        showRouteHistory = true
        pendingRouteHistoryRestore = false
    }

    private func presentPausedRouteNamingIfNeeded() {
        guard locationManager.needsPausedRouteNaming, !showPausedRouteNaming else { return }
        routeName = ""
        showPausedRouteNaming = true
    }

    private func syncActiveBoundaryOverlay() {
        locationManager.setActiveBoundaryOverlay(coordinates: overlayBoundary?.coordinates)
    }

    private func syncSegmentMarkerBaseline() {
        baselineSegmentMarkerIDs = Set(locationManager.segmentMarkers.map(\.id))
    }

    private func queueSegmentMarkerDropAnimations() {
        guard locationManager.isViewingActiveRoute else { return }

        for marker in locationManager.segmentMarkers {
            guard !baselineSegmentMarkerIDs.contains(marker.id),
                  !pendingMarkerDrops.contains(where: { $0.id == marker.id }) else {
                continue
            }

            pendingMarkerDrops.append(
                PendingMarkerDrop(
                    id: marker.id,
                    label: marker.label,
                    coordinate: marker.coordinate
                )
            )
        }
    }

    private func completeMarkerDrop(id: UUID) {
        baselineSegmentMarkerIDs.insert(id)
        pendingMarkerDrops.removeAll { $0.id == id }
    }

    private func isMarkerPendingDrop(_ id: UUID) -> Bool {
        pendingMarkerDrops.contains { $0.id == id }
    }
}

private struct LiveRecordingElapsedView: View {
    @ObservedObject var locationManager: LocationManager

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 4) {
                Text(
                    RouteDateFormatting.formatDuration(
                        locationManager.activeRoute?.recordingElapsedDuration(at: context.date) ?? 0
                    )
                )
                .font(.title2)
                .fontWeight(.bold)
                .monospacedDigit()
                Text("Elapsed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private enum EndRouteNamingSheetMode {
    case endRoute
    case pausedRouteOnReopen
}

private struct PendingMarkerDrop: Identifiable {
    let id: UUID
    let label: String
    let coordinate: CLLocationCoordinate2D
}

private struct RouteSegmentMarkerPin: View {
    let label: String

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(.black)
                    .frame(width: 28, height: 28)
                Text(label)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }

            RoutePinPoint()
                .fill(.black)
                .frame(width: 14, height: 10)
                .offset(y: -3)
        }
    }
}

private struct SegmentMarkerDropOverlay: View {
    let label: String
    let targetPoint: CGPoint
    let onComplete: () -> Void

    private static let pinHeight: CGFloat = 38

    @State private var bottomY: CGFloat = 0
    @State private var scaleX: CGFloat = 1
    @State private var scaleY: CGFloat = 1
    @State private var didStartAnimation = false

    var body: some View {
        RouteSegmentMarkerPin(label: label)
            .scaleEffect(x: scaleX, y: scaleY, anchor: .bottom)
            .position(
                x: targetPoint.x,
                y: bottomY - Self.pinHeight / 2
            )
            .allowsHitTesting(false)
            .onAppear {
                playDropAnimationIfNeeded()
            }
    }

    private func playDropAnimationIfNeeded() {
        guard !didStartAnimation else { return }
        didStartAnimation = true
        bottomY = 0

        withAnimation(.easeIn(duration: 0.55)) {
            bottomY = targetPoint.y
        } completion: {
            playLandingSquashAndBounce()
        }
    }

    private func playLandingSquashAndBounce() {
        withAnimation(.easeOut(duration: 0.08)) {
            scaleY = 0.6
            scaleX = 1.3
        } completion: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.42)) {
                scaleY = 1.1
                scaleX = 0.92
            } completion: {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                    scaleY = 1
                    scaleX = 1
                } completion: {
                    onComplete()
                }
            }
        }
    }
}

private struct RoutePinPoint: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

private struct EndRouteNamingSheet: View {
    let mode: EndRouteNamingSheetMode
    @Binding var routeName: String
    @ObservedObject var locationManager: LocationManager
    let onEnd: (String, String?, String?, String?) -> Void
    let onResume: () -> Void

    @State private var selectedMethod = RouteMethodsStorage.noneOption
    @State private var otherMethodText = ""
    @State private var selectedNeighborhoodType = NeighborhoodTypesStorage.noneOption
    @State private var otherNeighborhoodTypeText = ""
    @State private var selectedHighlighterColor = HighlighterColors.noneOption
    @State private var otherHighlighterColorText = ""

    private var trimmedName: String {
        routeName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var resolvedMethod: String? {
        RouteMethodsStorage.resolvedMethod(
            selectedMethod: selectedMethod,
            otherMethodText: otherMethodText
        )
    }

    private var resolvedNeighborhoodType: String? {
        NeighborhoodTypesStorage.resolvedType(
            selectedType: selectedNeighborhoodType,
            otherTypeText: otherNeighborhoodTypeText
        )
    }

    private var resolvedHighlighterColor: String? {
        HighlighterColors.resolvedColor(
            selectedColor: selectedHighlighterColor,
            otherColorText: otherHighlighterColorText
        )
    }

    private var isDuplicateName: Bool {
        !trimmedName.isEmpty &&
        !locationManager.isRouteNameAvailable(trimmedName, excludingRouteId: locationManager.activeRouteId)
    }

    private var canEnd: Bool {
        !trimmedName.isEmpty && !isDuplicateName
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Route name", text: $routeName)
                        .textInputAutocapitalization(.words)
                } footer: {
                    if isDuplicateName {
                        Text("A route with this name already exists. Choose a different name.")
                            .foregroundStyle(.red)
                    } else if mode == .pausedRouteOnReopen {
                        Text("Name this route before continuing your paused walk.")
                            .foregroundStyle(.secondary)
                    }
                }

                RouteMethodPickerSection(
                    selectedMethod: $selectedMethod,
                    otherMethodText: $otherMethodText
                )

                NeighborhoodTypePickerSection(
                    selectedType: $selectedNeighborhoodType,
                    otherTypeText: $otherNeighborhoodTypeText
                )

                HighlighterColorPickerSection(
                    selectedColor: $selectedHighlighterColor,
                    otherColorText: $otherHighlighterColorText
                )
            }
            .navigationTitle(mode == .endRoute ? "End Route" : "Name Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if mode == .endRoute {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Resume") {
                            onResume()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode == .endRoute ? "End Route" : "Continue") {
                        onEnd(
                            trimmedName,
                            resolvedMethod,
                            resolvedNeighborhoodType,
                            resolvedHighlighterColor
                        )
                    }
                    .disabled(!canEnd)
                }
            }
            .onAppear {
                selectedMethod = RouteMethodsStorage.noneOption
                otherMethodText = ""
                selectedNeighborhoodType = NeighborhoodTypesStorage.noneOption
                otherNeighborhoodTypeText = ""
                selectedHighlighterColor = HighlighterColors.noneOption
                otherHighlighterColorText = ""
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(mode == .pausedRouteOnReopen)
    }
}

#Preview {
    NavigationStack {
        RouteTrackingView(locationManager: LocationManager())
            .environmentObject(RouteMethodsStore())
            .environmentObject(NeighborhoodTypesStore())
            .environmentObject(AreaBoundariesStore())
    }
}
