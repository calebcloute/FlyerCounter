import Combine
import CoreLocation
import Foundation
import UIKit

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
    @Published private(set) var autoFlyerDetectionStatus: String?
    @Published private(set) var autoFlyerStatusUpdatedAt: Date?
    @Published private(set) var activePlannedRouteCoordinates: [CLLocationCoordinate2D] = []
    @Published private(set) var liveRouteStats: RouteLiveStats = .idle
    @Published private(set) var savedRouteAnalytics: [RouteSessionSnapshot] = []

    private let manager = CLLocationManager()
    private var lastRecordedLocation: CLLocation?
    private var pendingStart = false
    private var pendingNewRoute = false
    private var activeBoundaryCoordinates: [CLLocationCoordinate2D]?
    private var isNearActiveBoundary = false
    private let boundaryAlertManager = BoundaryAlertManager()
    private let minimumUpdateDistance: CLLocationDistance = 2
    private let minimumTravelHeadingSpeed: CLLocationSpeed = 0.5
    private let minimumTravelHeadingDistance: CLLocationDistance = 0.5
    private let maximumHeadingAccuracy: CLLocationDirection = 25
    private var autoFlyerSettings = AutoFlyerSettings()
    private var boundaryAlertSettings = BoundaryAlertSettings()
    private var compassTurnaroundFlyerDetector = CompassTurnaroundFlyerDetector()
    private var plannedRouteDivergenceFlyerDetector = PlannedRouteDivergenceFlyerDetector()
    private var pathBacktrackFlyerDetector = PathBacktrackFlyerDetector()
    private var autoFlyerEvaluationTask: Task<Void, Never>?
    private var backgroundActivitySession: CLBackgroundActivitySession?
    private var currentDeviceHeading: CLLocationDirection?
    private var lastTravelHeadingLocation: CLLocation?
    private var routeSessionTracker = RouteSessionTracker()

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
        reloadSavedRouteAnalytics()
        BoundaryNotificationScheduler.prepare()
        AutoFlyerCountFeedback.prepare()
        VoiceFeedback.prepare()
    }

    private func reloadSavedRouteAnalytics() {
        savedRouteAnalytics = RouteAnalyticsStorage.loadAll()
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

    var canRemoveLastFlyerDrop: Bool {
        isTracking && isViewingActiveRoute && flyerCount > 0
    }

    func refreshBackgroundRecordingIfNeeded() {
        guard isTracking, isLocationAuthorized else { return }
        configureBackgroundLocationIfNeeded()
        guard shouldMonitorLocation else { return }
        manager.startUpdatingLocation()
        refreshBackgroundAutoFlyerHeadingIfNeeded()
    }

    func prepareForBackground() {
        guard isTracking else { return }
        RouteStorage.setWasBackgroundedWhileRecording(true)
        activateBackgroundRecordingSupport()
        persistArchive()
        refreshBackgroundRecordingIfNeeded()
        VoiceFeedback.prepareForBackgroundPlayback()
        startAutoFlyerEvaluationLoopIfNeeded()
    }

    func prepareForForegroundReturn() {
        RouteStorage.setWasBackgroundedWhileRecording(false)
        refreshAuthorizationStatus()
        updateStatusMessage()
        refreshPausedRouteNamingRequirement()

        guard isLocationAuthorized else { return }

        if isTracking {
            activateBackgroundRecordingSupport()
            startLocationUpdatesIfNeeded()
            refreshHeadingUpdatesIfNeeded()
            startAutoFlyerEvaluationLoopIfNeeded()
        } else {
            startLocationUpdatesIfNeeded()
        }
    }

    private func activateBackgroundRecordingSupport() {
        guard isTracking, hasBackgroundLocationAuthorization, hasLocationBackgroundMode else { return }
        configureBackgroundLocationIfNeeded()
        if backgroundActivitySession == nil {
            backgroundActivitySession = CLBackgroundActivitySession()
        }
    }

    private func startAutoFlyerEvaluationLoopIfNeeded() {
        guard isTracking,
              autoFlyerSettings.method == .compassTurnaround,
              CLLocationManager.headingAvailable() else {
            stopAutoFlyerEvaluationLoop()
            return
        }

        if autoFlyerEvaluationTask != nil {
            evaluateAutomaticFlyerCounting()
            return
        }

        let interval = CompassTurnaroundFlyerDetector.historyRefreshIntervalSeconds
        autoFlyerEvaluationTask = Task { @MainActor [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                guard isTracking,
                      autoFlyerSettings.method == .compassTurnaround else {
                    break
                }

                evaluateAutomaticFlyerCounting()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }

            autoFlyerEvaluationTask = nil
        }

        evaluateAutomaticFlyerCounting()
    }

    private func stopAutoFlyerEvaluationLoop() {
        autoFlyerEvaluationTask?.cancel()
        autoFlyerEvaluationTask = nil
    }

    private func refreshBackgroundAutoFlyerHeadingIfNeeded() {
        guard isTracking,
              autoFlyerSettings.method == .compassTurnaround,
              CLLocationManager.headingAvailable() else { return }

        manager.headingFilter = kCLHeadingFilterNone
        manager.headingOrientation = .portrait
        manager.startUpdatingHeading()
        refreshAutoFlyerMonitoring()
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
        refreshHeadingUpdatesIfNeeded()
        AutoFlyerCountFeedback.requestAuthorizationIfNeeded()
    }

    func updateBoundaryAlertSettings(_ settings: BoundaryAlertSettings) {
        boundaryAlertSettings = settings
        boundaryAlertManager.apply(settings: settings)
        if !settings.isEnabled {
            isNearActiveBoundary = false
        }
    }

    func setActivePlannedRoute(coordinates: [CLLocationCoordinate2D]?) {
        activePlannedRouteCoordinates = coordinates ?? []
    }

    func setActiveBoundaryOverlay(coordinates: [CLLocationCoordinate2D]?) {
        if let coordinates, coordinates.count >= 2 {
            activeBoundaryCoordinates = coordinates
            if boundaryAlertSettings.isEnabled, boundaryAlertSettings.vibrateInBackground {
                BoundaryNotificationScheduler.requestAuthorizationIfNeeded()
            }
        } else {
            activeBoundaryCoordinates = nil
        }
        isNearActiveBoundary = false
        boundaryAlertManager.stop()
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

        RouteAnalyticsStorage.remove(routeId: id)
        reloadSavedRouteAnalytics()
        persistArchive()
        updateStatusMessage()
    }

    func deleteRouteAnalytics(at offsets: IndexSet) {
        for index in offsets {
            let snapshot = savedRouteAnalytics[index]
            RouteAnalyticsStorage.remove(routeId: snapshot.routeId)
        }
        reloadSavedRouteAnalytics()
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
        stopAutoFlyerEvaluationLoop()
        backgroundActivitySession?.invalidate()
        backgroundActivitySession = nil
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
        finalizeRouteAnalytics(routeName: trimmedName)
        startLocationUpdatesIfNeeded()
        refreshHeadingUpdatesIfNeeded()
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

        if source.isAutomatic {
            lastAutoFlyerDetectionMessage = note
            lastAutoFlyerDetectionDate = Date()
            AutoFlyerCountFeedback.deliver(note: note)
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
        lastTravelHeadingLocation = nil
        currentDeviceHeading = nil
        isTracking = true
        statusMessage = nil
        lastAutoFlyerDetectionMessage = nil
        lastAutoFlyerDetectionDate = nil
        compassTurnaroundFlyerDetector.beginRouteSession()
        plannedRouteDivergenceFlyerDetector.beginRouteSession()
        pathBacktrackFlyerDetector.beginRouteSession()
        VoiceFeedback.resetCooldownTracking()
        routeSessionTracker.reset()
        liveRouteStats = .idle
        startLocationUpdatesIfNeeded()
        refreshHeadingUpdatesIfNeeded()
        activateBackgroundRecordingSupport()
        persistArchive()
    }

    private func resumeRoute() {
        viewingRouteId = activeRouteId
        isTracking = true
        statusMessage = nil

        if !liveRouteStats.isSessionActive {
            routeSessionTracker.reset(startedAt: activeRoute?.startedAt ?? Date())
            liveRouteStats = RouteLiveStats(isSessionActive: true)
        }

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

        compassTurnaroundFlyerDetector.beginRouteSession()
        plannedRouteDivergenceFlyerDetector.beginRouteSession()
        pathBacktrackFlyerDetector.beginRouteSession()
        VoiceFeedback.resetCooldownTracking()
        startLocationUpdatesIfNeeded()
        refreshHeadingUpdatesIfNeeded()
        activateBackgroundRecordingSupport()
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
        routes = routes
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
        refreshHeadingUpdatesIfNeeded()
    }

    private func refreshHeadingUpdatesIfNeeded() {
        guard isTracking,
              autoFlyerSettings.method == .compassTurnaround,
              CLLocationManager.headingAvailable() else {
            manager.stopUpdatingHeading()
            currentDeviceHeading = nil
            refreshAutoFlyerMonitoring()
            return
        }

        manager.headingFilter = kCLHeadingFilterNone
        manager.headingOrientation = .portrait
        manager.startUpdatingHeading()
        refreshAutoFlyerMonitoring()
    }

    private func refreshAutoFlyerMonitoring() {
        let shouldDetect = isTracking
            && autoFlyerSettings.method == .compassTurnaround
            && CLLocationManager.headingAvailable()

        guard shouldDetect else {
            stopAutoFlyerEvaluationLoop()
            if !isTracking {
                autoFlyerDetectionStatus = nil
                autoFlyerStatusUpdatedAt = nil
            }
            return
        }

        startAutoFlyerEvaluationLoopIfNeeded()
    }

    private func refreshLatestDeviceHeadingFromManager() {
        if let heading = manager.heading {
            updateDeviceHeading(from: heading)
        }
    }

    private func latestSampledDeviceHeading() -> Double? {
        if let heading = manager.heading, let resolved = resolvedHeading(from: heading) {
            return resolved
        }
        return currentDeviceHeading
    }

    private func resolvedHeading(from heading: CLHeading) -> Double? {
        guard heading.headingAccuracy >= 0,
              heading.headingAccuracy <= maximumHeadingAccuracy else {
            return nil
        }

        return heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
    }

    private func updateDeviceHeading(from heading: CLHeading) {
        guard let resolvedHeading = resolvedHeading(from: heading) else { return }
        currentDeviceHeading = resolvedHeading
    }

    private func travelHeading(for location: CLLocation) -> Double? {
        let speed = location.speed >= 0 ? location.speed : 0
        if speed >= minimumTravelHeadingSpeed, location.course >= 0 {
            return location.course
        }

        if let previous = lastTravelHeadingLocation {
            let distance = location.distance(from: previous)
            guard distance >= minimumTravelHeadingDistance else { return nil }
            return previous.travelBearing(to: location)
        }

        return nil
    }

    private func configureBackgroundLocationIfNeeded() {
        let wantsBackground = hasBackgroundLocationAuthorization && isTracking
        let canUseBackground = wantsBackground && hasLocationBackgroundMode
        let wasBackgroundEnabled = manager.allowsBackgroundLocationUpdates

        manager.showsBackgroundLocationIndicator = canUseBackground
        manager.allowsBackgroundLocationUpdates = canUseBackground
        refreshBackgroundActivitySession(canUseBackground: canUseBackground)

        if canUseBackground, !wasBackgroundEnabled, shouldMonitorLocation {
            manager.stopUpdatingLocation()
            manager.startUpdatingLocation()
        }

        updateTrackingStatusMessage()
    }

    private func refreshBackgroundActivitySession(canUseBackground: Bool) {
        if canUseBackground {
            if backgroundActivitySession == nil {
                backgroundActivitySession = CLBackgroundActivitySession()
            }
        } else {
            backgroundActivitySession?.invalidate()
            backgroundActivitySession = nil
        }
    }

    private func updateTrackingStatusMessage() {
        guard isTracking else { return }

        if !hasBackgroundLocationAuthorization {
            statusMessage =
                "Route only records while Flyer Counter is open. " +
                "Set Location to Always in Settings for lock screen recording."
            return
        }

        if !hasLocationBackgroundMode {
            statusMessage = "Lock screen recording isn't enabled in this build."
            return
        }

        statusMessage = nil
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
    }

    private func recordSessionAnalytics(for location: CLLocation) {
        guard isTracking else { return }
        let heading = travelHeading(for: location)
        liveRouteStats = routeSessionTracker.process(
            location: location,
            travelHeading: heading
        )
    }

    private func finalizeRouteAnalytics(routeName: String?) {
        guard let activeRouteId else { return }
        guard let snapshot = routeSessionTracker.finalize(
            routeId: activeRouteId,
            routeName: routeName
        ) else { return }

        RouteAnalyticsStorage.upsert(snapshot)
        reloadSavedRouteAnalytics()
        liveRouteStats = .idle
    }

    private func evaluateAutomaticFlyerCounting(for location: CLLocation? = nil) {
        guard isTracking else { return }

        let evaluation: AutoFlyerEvaluation
        let dropSource: FlyerDropSource

        switch autoFlyerSettings.method {
        case .compassTurnaround:
            refreshLatestDeviceHeadingFromManager()
            evaluation = compassTurnaroundFlyerDetector.evaluateLive(
                deviceHeading: latestSampledDeviceHeading(),
                settings: autoFlyerSettings.turnaround
            )
            dropSource = .autoCompassTurnaround
        case .pathBacktrack:
            guard let sampleLocation = location ?? currentLocation else { return }
            evaluation = pathBacktrackFlyerDetector.evaluate(
                location: sampleLocation,
                routePoints: activeRoute?.routePoints ?? [],
                settings: autoFlyerSettings.pathBacktrack
            )
            dropSource = .autoBacktrack
        case .plannedRouteDivergence:
            guard let sampleLocation = location ?? currentLocation else { return }
            evaluation = plannedRouteDivergenceFlyerDetector.evaluate(
                location: sampleLocation,
                planCoordinates: activePlannedRouteCoordinates,
                settings: autoFlyerSettings.plannedRoute
            )
            dropSource = .autoPlannedRoute
        }

        if isViewingActiveRoute {
            autoFlyerDetectionStatus = evaluation.statusMessage
            autoFlyerStatusUpdatedAt = Date()
        }

        if autoFlyerSettings.isVoiceFeedbackEnabled {
            VoiceFeedback.handle(
                evaluation: evaluation,
                preferences: autoFlyerSettings.voiceAnnouncements
            )
        }

        guard let result = evaluation.result else { return }

        let dropCoordinate: CLLocationCoordinate2D
        switch autoFlyerSettings.method {
        case .pathBacktrack:
            dropCoordinate = result.coordinate
        case .compassTurnaround, .plannedRouteDivergence:
            guard let dropLocation = location ?? currentLocation else { return }
            dropCoordinate = dropLocation.coordinate
        }

        recordFlyerDrop(
            at: CLLocation(latitude: dropCoordinate.latitude, longitude: dropCoordinate.longitude),
            source: dropSource,
            note: result.note
        )
    }

    private func currentEndCoordinate(for route: RouteRecord) -> CLLocationCoordinate2D? {
        currentLocation?.coordinate ?? route.routePoints.last?.coordinate
    }

    private func checkActiveBoundaryProximity(for location: CLLocation) {
        guard boundaryAlertSettings.isEnabled else {
            isNearActiveBoundary = false
            boundaryAlertManager.stop()
            return
        }

        guard let coordinates = activeBoundaryCoordinates, coordinates.count >= 2 else {
            isNearActiveBoundary = false
            boundaryAlertManager.stop()
            return
        }
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= boundaryAlertSettings.maximumGPSAccuracyMeters else {
            return
        }

        let shouldAlert = BoundaryProximity.shouldAlert(
            location: location,
            polygon: coordinates,
            settings: boundaryAlertSettings
        )
        let safelyInside = BoundaryProximity.isSafelyInside(
            location: location,
            polygon: coordinates,
            settings: boundaryAlertSettings
        )
        let awayFromLine = coordinates.count < 3 && !shouldAlert

        if shouldAlert {
            boundaryAlertManager.update(shouldAlert: true, settings: boundaryAlertSettings)
            isNearActiveBoundary = true
        } else if safelyInside || awayFromLine {
            boundaryAlertManager.stop()
            isNearActiveBoundary = false
        }
    }

    private func updateStatusMessage() {
        guard !isTracking else {
            updateTrackingStatusMessage()
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
                recordSessionAnalytics(for: location)
                lastTravelHeadingLocation = location
                appendRoutePoint(from: location)
                evaluateAutomaticFlyerCounting(for: location)
            }
            checkActiveBoundaryProximity(for: location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            updateDeviceHeading(from: newHeading)
            if isTracking {
                switch autoFlyerSettings.method {
                case .compassTurnaround:
                    evaluateAutomaticFlyerCounting()
                case .pathBacktrack, .plannedRouteDivergence:
                    break
                }
            }
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
                stopAutoFlyerEvaluationLoop()
                backgroundActivitySession?.invalidate()
                backgroundActivitySession = nil
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

private extension CLLocation {
    func travelBearing(to destination: CLLocation) -> Double {
        let lat1 = coordinate.latitude * .pi / 180
        let lat2 = destination.coordinate.latitude * .pi / 180
        let deltaLon = (destination.coordinate.longitude - coordinate.longitude) * .pi / 180

        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let bearing = atan2(y, x) * 180 / .pi
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }
}
