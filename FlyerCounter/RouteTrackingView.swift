import CoreLocation
import MapKit
import SwiftUI

struct RouteTrackingView: View {
    @ObservedObject var locationManager: LocationManager
    @EnvironmentObject private var areaBoundariesStore: AreaBoundariesStore
    @EnvironmentObject private var autoFlyerSettingsStore: AutoFlyerSettingsStore
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
    @State private var isControlPanelCollapsed = false
    @State private var controlPanelDragOffset: CGFloat = 0
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
            .overlay(alignment: .bottom) {
                collapsibleControlPanel
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
            presentPausedRouteNamingIfNeeded()
            restoreRouteHistoryIfNeeded()
            syncActiveBoundaryOverlay()
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
        .onChange(of: showEndRouteNaming) { _, isPresented in
            if isPresented {
                prepareRouteNamingFormFromActiveRoute()
            }
        }
        .onChange(of: showPausedRouteNaming) { _, isPresented in
            if isPresented {
                prepareRouteNamingFormFromActiveRoute()
            }
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
        Map(position: $cameraPosition) {
            if locationManager.isLocationAuthorized && locationManager.isViewingActiveRoute {
                UserAnnotation()
            }

            ForEach(locationManager.flyerDrops) { drop in
                Annotation("", coordinate: drop.coordinate, anchor: .center) {
                    Circle()
                        .fill(flyerDropColor(for: drop.resolvedSource))
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }

            ForEach(locationManager.segmentMarkers) { marker in
                Annotation("", coordinate: marker.coordinate, anchor: .bottom) {
                    RouteSegmentMarkerView(label: marker.label)
                }
            }

            if locationManager.routeCoordinates.count >= 2 {
                ForEach(Array(locationManager.walkingRouteSegments.enumerated()), id: \.offset) { _, segment in
                    if segment.count >= 2 {
                        MapPolyline(coordinates: segment)
                            .stroke(.blue, lineWidth: 4)
                    }
                }

                ForEach(Array(locationManager.walkingRouteGapConnections.enumerated()), id: \.offset) { _, gap in
                    if gap.count >= 2 {
                        MapPolyline(coordinates: gap)
                            .stroke(
                                .blue,
                                style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [8, 7])
                            )
                    }
                }
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
    private var collapsibleControlPanel: some View {
        VStack(spacing: 0) {
            controlPanelDragHandle

            controlPanelContent
                .frame(maxWidth: .infinity, alignment: .top)
                .frame(maxHeight: isControlPanelCollapsed ? 0 : nil, alignment: .top)
                .clipped()
                .opacity(isControlPanelCollapsed ? 0 : 1)
                .allowsHitTesting(!isControlPanelCollapsed)
        }
        .background(.ultraThinMaterial)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 16,
                topTrailingRadius: 16
            )
        )
        .offset(y: controlPanelDragOffset)
        .gesture(controlPanelDragGesture)
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: isControlPanelCollapsed)
    }

    private var controlPanelDragHandle: some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(.secondary.opacity(0.45))
                .frame(width: 40, height: 5)

            if isControlPanelCollapsed {
                Image(systemName: "chevron.up")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 10)
        .padding(.bottom, isControlPanelCollapsed ? 12 : 6)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            toggleControlPanelCollapsed()
        }
    }

    private var controlPanelDragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                let translation = value.translation.height
                if isControlPanelCollapsed {
                    controlPanelDragOffset = min(0, translation)
                } else {
                    controlPanelDragOffset = max(0, translation)
                }
            }
            .onEnded { value in
                let threshold: CGFloat = 72
                let translation = value.translation.height
                let predicted = value.predictedEndTranslation.height

                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    if isControlPanelCollapsed {
                        if translation < -threshold || predicted < -threshold {
                            isControlPanelCollapsed = false
                        }
                    } else if translation > threshold || predicted > threshold {
                        isControlPanelCollapsed = true
                    }
                    controlPanelDragOffset = 0
                }
            }
    }

    private func toggleControlPanelCollapsed() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
            isControlPanelCollapsed.toggle()
            controlPanelDragOffset = 0
        }
        haptic(.light)
    }

    @ViewBuilder
    private var controlPanelContent: some View {
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
                autoFlyerCountingStatus

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
                    prepareRouteNamingFormFromActiveRoute()
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
    }

    @ViewBuilder
    private var autoFlyerCountingStatus: some View {
        if autoFlyerSettingsStore.settings.isEnabled {
            let method = autoFlyerSettingsStore.settings.method
            VStack(spacing: 4) {
                Label(
                    "Auto counting: \(method.label)",
                    systemImage: method == .compassTurnaround ? "arrow.uturn.down" : "point.topleft.down.to.point.bottomright.filled.curvepath"
                )
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(method == .compassTurnaround ? .blue : .green)

                Text(locationManager.backtrackDetectionStatus ?? method.statusDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let message = locationManager.lastAutoFlyerDetectionMessage,
                   let date = locationManager.lastAutoFlyerDetectionDate {
                    Text("Last auto count · \(message) · \(autoCountRelativeDate(date))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func flyerDropColor(for source: FlyerDropSource) -> Color {
        switch source {
        case .manual:
            .orange
        case .autoBacktrack:
            .green
        case .autoCompassTurnaround:
            .blue
        }
    }

    private func autoCountRelativeDate(_ date: Date) -> String {
        let interval = max(0, Int(Date().timeIntervalSince(date)))
        if interval < 60 {
            return "\(interval)s ago"
        }
        return "\(interval / 60)m ago"
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
        prepareRouteNamingFormFromActiveRoute()
        showPausedRouteNaming = true
    }

    private func prepareRouteNamingFormFromActiveRoute() {
        routeName = locationManager.activeRoute?.trimmedName ?? ""
    }

    private func syncActiveBoundaryOverlay() {
        locationManager.setActiveBoundaryOverlay(coordinates: overlayBoundary?.coordinates)
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

private struct RouteSegmentMarkerView: View {
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
    @EnvironmentObject private var routeMethodsStore: RouteMethodsStore
    @EnvironmentObject private var neighborhoodTypesStore: NeighborhoodTypesStore
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
                            saveDraftToActiveRouteIfPossible()
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
                initializeFormFromActiveRoute()
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(mode == .pausedRouteOnReopen)
    }

    private func initializeFormFromActiveRoute() {
        guard let route = locationManager.activeRoute else {
            resetPickerFields()
            return
        }

        if let name = route.trimmedName {
            routeName = name
        }

        initializeMethodSelection(from: route)
        initializeNeighborhoodTypeSelection(from: route)
        initializeHighlighterColorSelection(from: route)
    }

    private func resetPickerFields() {
        selectedMethod = RouteMethodsStorage.noneOption
        otherMethodText = ""
        selectedNeighborhoodType = NeighborhoodTypesStorage.noneOption
        otherNeighborhoodTypeText = ""
        selectedHighlighterColor = HighlighterColors.noneOption
        otherHighlighterColorText = ""
    }

    private func initializeMethodSelection(from route: RouteRecord) {
        guard let method = route.trimmedMethod else {
            selectedMethod = RouteMethodsStorage.noneOption
            otherMethodText = ""
            return
        }

        if let match = routeMethodsStore.methods.first(where: {
            $0.compare(method, options: .caseInsensitive) == .orderedSame
        }) {
            selectedMethod = match
            otherMethodText = ""
        } else {
            selectedMethod = RouteMethodsStorage.otherOption
            otherMethodText = method
        }
    }

    private func initializeNeighborhoodTypeSelection(from route: RouteRecord) {
        guard let neighborhoodType = route.trimmedNeighborhoodType else {
            selectedNeighborhoodType = NeighborhoodTypesStorage.noneOption
            otherNeighborhoodTypeText = ""
            return
        }

        if let match = neighborhoodTypesStore.types.first(where: {
            $0.compare(neighborhoodType, options: .caseInsensitive) == .orderedSame
        }) {
            selectedNeighborhoodType = match
            otherNeighborhoodTypeText = ""
        } else {
            selectedNeighborhoodType = NeighborhoodTypesStorage.otherOption
            otherNeighborhoodTypeText = neighborhoodType
        }
    }

    private func initializeHighlighterColorSelection(from route: RouteRecord) {
        let state = HighlighterColors.initialPickerState(for: route.trimmedHighlighterColor)
        selectedHighlighterColor = state.selected
        otherHighlighterColorText = state.otherText
    }

    private func saveDraftToActiveRouteIfPossible() {
        guard !trimmedName.isEmpty,
              locationManager.isRouteNameAvailable(
                trimmedName,
                excludingRouteId: locationManager.activeRouteId
              ) else {
            return
        }

        _ = locationManager.saveActiveRouteDetails(
            name: trimmedName,
            method: resolvedMethod,
            neighborhoodType: resolvedNeighborhoodType,
            highlighterColor: resolvedHighlighterColor
        )
    }
}

#Preview {
    NavigationStack {
        RouteTrackingView(locationManager: LocationManager())
            .environmentObject(RouteMethodsStore())
            .environmentObject(NeighborhoodTypesStore())
            .environmentObject(AreaBoundariesStore())
            .environmentObject(AutoFlyerSettingsStore())
    }
}
