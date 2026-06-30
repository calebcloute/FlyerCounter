import SwiftUI

private enum AppTab: Int {
    case routeTracking = 0
    case routePlanner = 1
    case testingStats = 2
    case settings = 3
}

struct ContentView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var routeMethodsStore = RouteMethodsStore()
    @StateObject private var neighborhoodTypesStore = NeighborhoodTypesStore()
    @StateObject private var areaBoundariesStore = AreaBoundariesStore()
    @StateObject private var plannedRouteStore = PlannedRouteStore()
    @StateObject private var autoFlyerSettingsStore = AutoFlyerSettingsStore()
    @StateObject private var settingsLockStore = SettingsLockStore()
    @StateObject private var boundaryAlertSettingsStore = BoundaryAlertSettingsStore()

    @AppStorage("selectedTab") private var selectedTab = AppTab.routeTracking.rawValue
    @AppStorage("activeOverlayBoundaryId") private var activeOverlayBoundaryIdRaw = ""
    @AppStorage("didMigrateTestingTab") private var didMigrateTestingTab = false
    @AppStorage("didMigratePlannerTab") private var didMigratePlannerTab = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                RouteTrackingView(locationManager: locationManager)
            }
            .tabItem {
                Label("Route Tracking", systemImage: "map")
            }
            .tag(AppTab.routeTracking.rawValue)

            RoutePlannerView()
                .tabItem {
                    Label("Route Planner", systemImage: "point.bottomleft.forward.to.point.topright.scurvepath")
                }
                .tag(AppTab.routePlanner.rawValue)

            TestingStatsView(locationManager: locationManager)
                .tabItem {
                    Label("Testing", systemImage: "chart.xyaxis.line")
                }
                .tag(AppTab.testingStats.rawValue)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(AppTab.settings.rawValue)
        }
        .environmentObject(routeMethodsStore)
        .environmentObject(neighborhoodTypesStore)
        .environmentObject(areaBoundariesStore)
        .environmentObject(plannedRouteStore)
        .environmentObject(autoFlyerSettingsStore)
        .environmentObject(settingsLockStore)
        .environmentObject(boundaryAlertSettingsStore)
        .onAppear {
            migrateSelectedTabIfNeeded()
            autoFlyerSettingsStore.bind(settingsLockStore: settingsLockStore)
            locationManager.updateAutoFlyerSettings(autoFlyerSettingsStore.settings)
            locationManager.updateBoundaryAlertSettings(boundaryAlertSettingsStore.settings)
            locationManager.prepareForUse()
            syncActiveBoundaryOverlay()
            syncActivePlannedRoute()
            showRouteTrackingForPausedNamingIfNeeded()
        }
        .onChange(of: autoFlyerSettingsStore.settings) { _, newSettings in
            locationManager.updateAutoFlyerSettings(newSettings)
        }
        .onChange(of: boundaryAlertSettingsStore.settings) { _, newSettings in
            locationManager.updateBoundaryAlertSettings(newSettings)
        }
        .onChange(of: activeOverlayBoundaryIdRaw) { _, _ in
            syncActiveBoundaryOverlay()
        }
        .onChange(of: plannedRouteStore.activeRouteId) { _, _ in
            syncActivePlannedRoute()
        }
        .onChange(of: plannedRouteStore.routes) { _, _ in
            syncActivePlannedRoute()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                locationManager.updateAutoFlyerSettings(autoFlyerSettingsStore.settings)
                locationManager.updateBoundaryAlertSettings(boundaryAlertSettingsStore.settings)
                locationManager.prepareForForegroundReturn()
                syncActiveBoundaryOverlay()
                syncActivePlannedRoute()
                showRouteTrackingForPausedNamingIfNeeded()
            case .inactive, .background:
                locationManager.prepareForBackground()
            default:
                break
            }
        }
    }

    private func migrateSelectedTabIfNeeded() {
        if !didMigrateTestingTab {
            if selectedTab == 1 {
                selectedTab = AppTab.settings.rawValue
            }
            didMigrateTestingTab = true
        }

        guard !didMigratePlannerTab else { return }
        if selectedTab >= AppTab.routePlanner.rawValue {
            selectedTab += 1
        }
        didMigratePlannerTab = true
    }

    private func syncActivePlannedRoute() {
        locationManager.setActivePlannedRoute(
            coordinates: plannedRouteStore.activeRoute?.pathCoordinates
        )
    }

    private func syncActiveBoundaryOverlay() {
        if let id = UUID(uuidString: activeOverlayBoundaryIdRaw),
           let boundary = areaBoundariesStore.boundary(id: id) {
            locationManager.setActiveBoundaryOverlay(coordinates: boundary.coordinates)
        } else {
            locationManager.setActiveBoundaryOverlay(coordinates: nil)
        }
    }

    private func showRouteTrackingForPausedNamingIfNeeded() {
        guard locationManager.needsPausedRouteNaming else { return }
        selectedTab = AppTab.routeTracking.rawValue
    }
}

#Preview {
    ContentView()
}
