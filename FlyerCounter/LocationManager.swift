import Combine
import CoreLocation
import Foundation

@MainActor
final class LocationManager: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var routes: [RouteRecord] = []
    @Published private(set) var activeRouteId: UUID?
    @Published private(set) var viewingRouteId: UUID?
    @Published private(set) var isTracking = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var needsPausedRouteNaming = false
    @Published private(set) var lastAutoFlyerDetectionMessage: String?
    @Published private(set) var lastAutoFlyerDetectionDate: Date?

    private let manager = CLLocationManager()
    private var lastRecordedLocation: CLLocation?
    private var pendingStart = false
    private var pendingNewRoute = false
    private var activeBoundaryCoordinates: [CLLocationCoordinate2D]?
    private var isNearActiveBoundary = false
    private let minimumUpdateDistance: CLLocationDistance = 2
    private var autoFlyerSettings = AutoFlyerSettings()
    private var backtrackFlyerDetector = BacktrackFlyerDetector()

    var displayedRoute: RouteRecord? {
        let id = viewingRouteId ?? activeRouteId
        guard let id else { return nil }
        return routes.first { $0.id == id }
    }

    var activeRoute: RouteRecord? {
        guard let activeRouteId else { return nil }
        return routes.first { $0.id == activeRouteId }
    }

    var routeCoordinates: [CLLocationCoordinate2D] {
        displayedRoute?.routePoints.map { $0.coordinate } ?? []
    }

    var walkingRouteSegments: [[CLLocationCoordinate2D]] {
        displayedRoute?.walkingSegmentsCoordinates() ?? []
    }

    var walkingRouteGapConnections: [[CLLocationCoordinate2D]] {
        displayedRoute?.walkingGapConnections() ?? []
    }

    var flyerDrops: [FlyerDrop] {
        displayedRoute?.flyerDrops ?? []
    }

    var segmentMarkers: [RouteSegmentMarker] {
        displayedRoute?.resolvedSegmentMarkers ?? []
    }

    var flyerCount: Int {
        displayedRoute?.flyerCount ?? 0
    }

    var hasRouteData: Bool {
        guard let route = activeRoute else { return false }
        return !route.routePoints.isEmpty || route.flyerCount > 0
    }

    var hasUnnamedActiveRoute: Bool {
        guard let route = activeRoute, route.isInProgress else { return false }
        return route.trimmedName == nil && hasRouteData && !isTracking
    }

    var isViewingActiveRoute: Bool {
        guard let activeRouteId else { return viewingRouteId == nil }
        return viewingRouteId == nil || viewingRouteId == activeRouteId
    }

    var savedRoutes: [RouteRecord] {
        routes.sorted { $0.startedAt > $1.startedAt }
    }

    var distanceWalked: CLLocationDistance {
        displayedRoute?.distanceWalked ?? 0
    }

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .fitness
        manager.pausesLocationUpdatesAutomatically = false
        loadArchive()
    }

    private var hasLocationBackgroundMode: Bool {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") else {
            return false
        }

        if let modes = value as? [String] {
            return modes.contains("location")
        }

        if let modes = value as? NSArray {
            return modes.contains { ($0 as? String) == "location" }
        }

        if let mode = value as? String {
            return mode == "location" || mode.split(separator: " ").contains("location")
        }

        return false
    }

    var isLocationAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var hasBackgroundLocationAuthorization: Bool {
        authorizationStatus == .authorizedAlways
    }

    var isLocationDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    var canRecordFlyerDrop: Bool {
        isTracking && isViewingActiveRoute && currentLocation != nil
    }

    var canRemoveLastFlyerDrop: Bool {
        isTracking && isViewingActiveRoute && flyerCount > 0
    }

    func prepareForUse() {
        refreshAuthorizationStatus()
        updateStatusMessage()
        refreshPausedRouteNamingRequirement()

        if isLocationAuthorized {
            startLocationUpdatesIfNeeded()
        }
    }

    func updateAutoFlyerSettings(_ settings: AutoFlyerSettings) {
        autoFlyerSettings = settings
    }

    func setActiveBoundaryOverlay(coordinates: [CLLocationCoordinate2D]?) {
        if let coordinates, coordinates.count >= 2 {
            activeBoundaryCoordinates = coordinates
        } else {
            activeBoundaryCoordinates = nil
        }
        isNearActiveBoundary = false
        startLocationUpdatesIfNeeded()
    }

    func refreshPausedRouteNamingRequirement() {
        needsPausedRouteNaming = hasUnnamedActiveRoute
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = manager.authorizationStatus
    }

    func selectRoute(id: UUID) {
        viewingRouteId = id
    }

    func returnToActiveRoute() {
        viewingRouteId = activeRouteId
    }

    func deleteRoute(id: UUID) {
        routes.removeAll { $0.id == id }

        if activeRouteId == id {
            activeRouteId = nil
            isTracking = false
            lastRecordedLocation = nil
        }

        if viewingRouteId == id {
            viewingRouteId = activeRouteId
        }

        persistArchive()
        updateStatusMessage()
    }

    @discardableResult
    func updateRoute(
        id: UUID,
        name: String,
        method: String?,
        neighborhoodType: String?,
        highlighterColor: String?
    ) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              isRouteNameAvailable(trimmedName, excludingRouteId: id),
              let index = routes.firstIndex(where: { $0.id == id }) else {
            return false
        }

        let trimmedMethod = method?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNeighborhoodType = neighborhoodType?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHighlighterColor = highlighterColor?.trimmingCharacters(in: .whitespacesAndNewlines)
        routes[index].name = trimmedName
        routes[index].method = trimmedMethod?.isEmpty == false ? trimmedMethod : nil
        routes[index].neighborhoodType = trimmedNeighborhoodType?.isEmpty == false ? trimmedNeighborhoodType : nil
        routes[index].highlighterColor = trimmedHighlighterColor?.isEmpty == false ? trimmedHighlighterColor : nil
        persistArchive()
        return true
    }

    @discardableResult
    func saveActiveRouteDetails(
        name: String,
        method: String?,
        neighborhoodType: String?,
        highlighterColor: String?
    ) -> Bool {
        guard let activeRouteId else { return false }
        let saved = updateRoute(
            id: activeRouteId,
            name: name,
            method: method,
            neighborhoodType: neighborhoodType,
            highlighterColor: highlighterColor
        )
        if saved {
            refreshPausedRouteNamingRequirement()
        }
        return saved
    }

    func requestNewRoute() {
        statusMessage = nil
        refreshAuthorizationStatus()

        guard CLLocationManager.locationServicesEnabled() else {
            statusMessage = "Location Services are turned off. Enable them in Settings → Privacy & Security → Location Services."
            return
        }

        switch authorizationStatus {
        case .notDetermined:
            pendingStart = true
            pendingNewRoute = true
            requestAlwaysLocationAuthorization()
        case .authorizedWhenInUse:
            pendingStart = true
            pendingNewRoute = true
            requestAlwaysLocationAuthorization()
            statusMessage = "Allow Always location access so your route keeps recording in the background."
        case .authorizedAlways:
            pendingStart = false
            pendingNewRoute = false
            beginNewRoute()
        case .denied, .restricted:
            statusMessage = "Location access is denied. Open Settings and set Flyer Counter to Always."
        @unknown default:
            statusMessage = "Location access is unavailable."
        }
    }

    func requestContinueRoute() {
        statusMessage = nil
        refreshAuthorizationStatus()

        guard CLLocationManager.locationServicesEnabled() else {
            statusMessage = "Location Services are turned off. Enable them in Settings → Privacy & Security → Location Services."
            return
        }

        guard isLocationAuthorized else {
            if authorizationStatus == .notDetermined {
                pendingStart = true
                pendingNewRoute = false
                requestAlwaysLocationAuthorization()
            } else {
                statusMessage = "Location access is denied. Open Settings and set Flyer Counter to Always."
            }
            return
        }

        pendingStart = false
        pendingNewRoute = false
        resumeRoute()
    }

    func stopTracking(
        name: String,
        method: String?,
        neighborhoodType: String?,
        highlighterColor: String?
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              isRouteNameAvailable(trimmedName, excludingRouteId: activeRouteId) else { return }

        let trimmedMethod = method?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNeighborhoodType = neighborhoodType?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHighlighterColor = highlighterColor?.trimmingCharacters(in: .whitespacesAndNewlines)

        isTracking = false
        updateActiveRoute { route in
            if let endCoordinate = currentEndCoordinate(for: route) {
                route.appendEndSegmentMarker(at: endCoordinate)
            }
            route.commitOpenRecordingSegment()
            route.endedAt = Date()
            route.pausedAt = nil
            route.name = trimmedName
            route.method = trimmedMethod?.isEmpty == false ? trimmedMethod : nil
            route.neighborhoodType = trimmedNeighborhoodType?.isEmpty == false ? trimmedNeighborhoodType : nil
            route.highlighterColor = trimmedHighlighterColor?.isEmpty == false ? trimmedHighlighterColor : nil
        }
        startLocationUpdatesIfNeeded()
        updateStatusMessage()
    }

    func isRouteNameAvailable(_ name: String, excludingRouteId: UUID? = nil) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }

        return !routes.contains { route in
            if route.id == excludingRouteId { return false }
            guard let existingName = route.trimmedName else { return false }
            return existingName.compare(trimmedName, options: .caseInsensitive) == .orderedSame
        }
    }

    func recordFlyerDrop() {
        guard let location = currentLocation else { return }
        recordFlyerDrop(at: location, source: .manual)
    }

    private func recordFlyerDrop(at location: CLLocation, source: FlyerDropSource, note: String? = nil) {
        updateActiveRoute { route in
            route.flyerDrops.append(
                FlyerDrop(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    source: source
                )
            )
            route.flyerCount += 1
        }

        if source != .manual {
            lastAutoFlyerDetectionMessage = note
            lastAutoFlyerDetectionDate = Date()
        }
    }

    func removeLastFlyerDrop() {
        guard canRemoveLastFlyerDrop else { return }

        updateActiveRoute { route in
            guard route.flyerCount > 0 else { return }
            if !route.flyerDrops.isEmpty {
                route.flyerDrops.removeLast()
            }
            route.flyerCount -= 1
        }
    }

    private func beginNewRoute() {
        guard isLocationAuthorized else {
            pendingStart = true
            pendingNewRoute = true
            requestAlwaysLocationAuthorization()
            statusMessage = "Allow location access to record your route."
            return
        }

        finalizeActiveRouteIfNeeded()

        let route = RouteRecord(
            id: UUID(),
            name: nil,
            method: nil,
            neighborhoodType: nil,
            highlighterColor: nil,
            startedAt: Date(),
            endedAt: nil,
            pausedAt: nil,
            accumulatedRecordingSeconds: 0,
            recordingStartedAt: Date(),
            routePoints: [],
            flyerDrops: [],
            flyerCount: 0,
            segmentMarkers: nil,
            walkingSegmentStartIndices: [0]
        )

        routes.insert(route, at: 0)
        activeRouteId = route.id
        viewingRouteId = route.id
        lastRecordedLocation = nil
        isTracking = true
        statusMessage = nil
        lastAutoFlyerDetectionMessage = nil
        lastAutoFlyerDetectionDate = nil
        backtrackFlyerDetector.reset()
        startLocationUpdatesIfNeeded()
        persistArchive()
    }

    private func resumeRoute() {
        viewingRouteId = activeRouteId
        isTracking = true
        statusMessage = nil

        updateActiveRoute { route in
            route.endedAt = nil
            route.pausedAt = nil
            route.beginRecordingSegment()
            route.markWalkingSegmentResume()
        }

        if let lastCoordinate = activeRoute?.routePoints.last?.coordinate {
            lastRecordedLocation = CLLocation(
                latitude: lastCoordinate.latitude,
                longitude: lastCoordinate.longitude
            )
        }

        startLocationUpdatesIfNeeded()
        persistArchive()
    }

    private func finalizeActiveRouteIfNeeded() {
        guard let activeRouteId,
              let index = routes.firstIndex(where: { $0.id == activeRouteId }) else { return }

        if routes[index].endedAt == nil {
            routes[index].endedAt = Date()
        }
    }

    private func markActiveRoutePausedIfNeeded() {
        guard let activeRouteId,
              let index = routes.firstIndex(where: { $0.id == activeRouteId }),
              routes[index].isInProgress,
              routes[index].pausedAt == nil else { return }

        var route = routes[index]
        if let recordingStartedAt = route.recordingStartedAt {
            let commitEnd = route.lastRecordingCheckpointAt ?? recordingStartedAt
            route.commitOpenRecordingSegment(at: commitEnd)
        }
        route.pausedAt = Date()
        routes[index] = route
        persistArchive()
    }

    private func updateActiveRoute(_ update: (inout RouteRecord) -> Void) {
        guard let activeRouteId,
              let index = routes.firstIndex(where: { $0.id == activeRouteId }) else { return }

        update(&routes[index])
        persistArchive()
    }

    private func loadArchive() {
        if let archive = RouteStorage.loadArchive() {
            routes = archive.routes
            activeRouteId = archive.activeRouteId
            viewingRouteId = archive.activeRouteId
            isTracking = false
            markActiveRoutePausedIfNeeded()

            if let lastCoordinate = activeRoute?.routePoints.last?.coordinate {
                lastRecordedLocation = CLLocation(
                    latitude: lastCoordinate.latitude,
                    longitude: lastCoordinate.longitude
                )
            }
            refreshPausedRouteNamingRequirement()
            return
        }

        if let legacy = RouteStorage.loadLegacyRoute() {
            let route = RouteRecord(
                id: UUID(),
                name: nil,
                method: nil,
                neighborhoodType: nil,
                highlighterColor: nil,
                startedAt: Date(),
                endedAt: legacy.isTracking ? nil : Date(),
                pausedAt: legacy.isTracking ? Date() : nil,
                accumulatedRecordingSeconds: 0,
                recordingStartedAt: nil,
                routePoints: legacy.routePoints,
                flyerDrops: legacy.flyerDrops,
                flyerCount: legacy.flyerCount,
                segmentMarkers: nil
            )
            routes = [route]
            activeRouteId = route.id
            viewingRouteId = route.id
            isTracking = false
            RouteStorage.removeLegacyRoute()
            persistArchive()
        }

        refreshPausedRouteNamingRequirement()
    }

    private func persistArchive() {
        checkpointActiveRouteRecordingTimeInPlace()

        let archive = RouteArchive(
            routes: routes,
            activeRouteId: activeRouteId
        )
        RouteStorage.saveArchive(archive)
    }

    private func checkpointActiveRouteRecordingTimeInPlace() {
        guard isTracking,
              let activeRouteId,
              let index = routes.firstIndex(where: { $0.id == activeRouteId }),
              let recordingStartedAt = routes[index].recordingStartedAt else { return }

        let now = Date()
        var route = routes[index]
        route.accumulatedRecordingSeconds += now.timeIntervalSince(recordingStartedAt)
        route.recordingStartedAt = now
        route.lastRecordingCheckpointAt = now
        routes[index] = route
    }

    private func startLocationUpdatesIfNeeded() {
        refreshAuthorizationStatus()

        guard isLocationAuthorized, shouldMonitorLocation else {
            stopLocationUpdatesIfNeeded()
            return
        }

        configureBackgroundLocationIfNeeded()
        manager.startUpdatingLocation()
    }

    private var shouldMonitorLocation: Bool {
        isTracking || activeBoundaryCoordinates != nil
    }

    private func stopLocationUpdatesIfNeeded() {
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
    }

    private func configureBackgroundLocationIfNeeded() {
        let enableBackground = hasBackgroundLocationAuthorization
            && isTracking
            && hasLocationBackgroundMode

        manager.showsBackgroundLocationIndicator = enableBackground
        manager.allowsBackgroundLocationUpdates = enableBackground

        if hasBackgroundLocationAuthorization, isTracking, !hasLocationBackgroundMode {
            statusMessage = "Route recording works in the app, but background recording needs Location Updates enabled under Background Modes in Xcode."
        }
    }

    private func requestAlwaysLocationAuthorization() {
        manager.requestAlwaysAuthorization()
    }

    private func appendRoutePoint(from location: CLLocation) {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 25 else { return }

        if let lastRecordedLocation {
            guard location.distance(from: lastRecordedLocation) >= minimumUpdateDistance else { return }
        }

        updateActiveRoute { route in
            route.routePoints.append(StoredCoordinate(coordinate: location.coordinate))
            if route.resolvedSegmentMarkers.isEmpty {
                route.ensureStartMarker(at: location.coordinate)
            }
        }
        lastRecordedLocation = location
        evaluateAutomaticFlyerCounting(for: location)
    }

    private func evaluateAutomaticFlyerCounting(for location: CLLocation) {
        guard isTracking,
              isViewingActiveRoute,
              autoFlyerSettings.isEnabled,
              let route = activeRoute else {
            return
        }

        guard let result = backtrackFlyerDetector.evaluate(
            routePoints: route.routePoints,
            settings: autoFlyerSettings.backtrack
        ) else {
            return
        }

        recordFlyerDrop(at: location, source: .autoBacktrack, note: result.note)
    }

    private func currentEndCoordinate(for route: RouteRecord) -> CLLocationCoordinate2D? {
        currentLocation?.coordinate ?? route.routePoints.last?.coordinate
    }

    private func checkActiveBoundaryProximity(for location: CLLocation) {
        guard let coordinates = activeBoundaryCoordinates, coordinates.count >= 2 else {
            isNearActiveBoundary = false
            return
        }
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= BoundaryProximity.maximumLocationAccuracy else {
            return
        }

        let distance = BoundaryProximity.nearestDistance(from: location, toClosedPolygon: coordinates)
        if distance <= BoundaryProximity.alertDistanceMeters {
            if !isNearActiveBoundary {
                BoundaryProximity.playNearbyAlert()
            }
            isNearActiveBoundary = true
        } else if distance > BoundaryProximity.resetDistanceMeters {
            isNearActiveBoundary = false
        }
    }

    private func updateStatusMessage() {
        guard !isTracking else {
            if hasBackgroundLocationAuthorization, !hasLocationBackgroundMode {
                statusMessage = "Route recording works in the app, but background recording needs Location Updates enabled under Background Modes in Xcode."
            } else {
                statusMessage = nil
            }
            return
        }

        if !CLLocationManager.locationServicesEnabled() {
            statusMessage = "Location Services are turned off. Enable them in Settings → Privacy & Security → Location Services."
        } else if isLocationDenied {
            statusMessage = "Location access is denied. Open Settings and set Flyer Counter to Always."
        } else if authorizationStatus == .authorizedWhenInUse {
            statusMessage = "Allow Always location access so your route keeps recording in the background."
        } else if authorizationStatus == .notDetermined {
            statusMessage = "Tap Start Route and allow location access when prompted."
        } else {
            statusMessage = nil
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus

            if pendingStart {
                if isLocationAuthorized {
                    pendingStart = false
                    if pendingNewRoute {
                        pendingNewRoute = false
                        beginNewRoute()
                    } else if hasRouteData {
                        resumeRoute()
                    } else {
                        beginNewRoute()
                    }
                } else if isLocationDenied {
                    pendingStart = false
                    pendingNewRoute = false
                    updateStatusMessage()
                } else if pendingStart, authorizationStatus == .authorizedWhenInUse {
                    statusMessage = "For background recording, set Flyer Counter to Always in Settings → Location."
                }
            }

            if isLocationAuthorized {
                startLocationUpdatesIfNeeded()
            } else {
                stopLocationUpdatesIfNeeded()
            }

            updateStatusMessage()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            currentLocation = location
            if isTracking {
                appendRoutePoint(from: location)
            }
            checkActiveBoundaryProximity(for: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            guard let error = error as? CLError else { return }

            switch error.code {
            case .denied:
                authorizationStatus = manager.authorizationStatus
                pendingStart = false
                pendingNewRoute = false
                isTracking = false
                persistArchive()
                updateStatusMessage()
            case .locationUnknown:
                break
            default:
                statusMessage = "Unable to get your location. Try moving outdoors and try again."
            }
        }
    }
}
