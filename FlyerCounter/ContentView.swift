import SwiftUI

private enum AppTab: Int {
    case routeTracking = 0
    case testingStats = 1
    case settings = 2
}

struct ContentView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var routeMethodsStore = RouteMethodsStore()
    @StateObject private var neighborhoodTypesStore = NeighborhoodTypesStore()
    @StateObject private var areaBoundariesStore = AreaBoundariesStore()
    @StateObject private var autoFlyerSettingsStore = AutoFlyerSettingsStore()
    @StateObject private var boundaryAlertSettingsStore = BoundaryAlertSettingsStore()

    @AppStorage("selectedTab") private var selectedTab = AppTab.routeTracking.rawValue
    @AppStorage("activeOverlayBoundaryId") private var activeOverlayBoundaryIdRaw = ""
    @AppStorage("didMigrateTestingTab") private var didMigrateTestingTab = false
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
        .environmentObject(autoFlyerSettingsStore)
        .environmentObject(boundaryAlertSettingsStore)
        .onAppear {
            migrateSelectedTabIfNeeded()
            locationManager.updateAutoFlyerSettings(autoFlyerSettingsStore.settings)
            locationManager.updateBoundaryAlertSettings(boundaryAlertSettingsStore.settings)
            locationManager.prepareForUse()
            syncActiveBoundaryOverlay()
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
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                locationManager.updateAutoFlyerSettings(autoFlyerSettingsStore.settings)
                locationManager.updateBoundaryAlertSettings(boundaryAlertSettingsStore.settings)
                locationManager.prepareForUse()
                syncActiveBoundaryOverlay()
                showRouteTrackingForPausedNamingIfNeeded()
            case .inactive, .background:
                locationManager.refreshBackgroundRecordingIfNeeded()
            default:
                break
            }
        }
    }

    private func migrateSelectedTabIfNeeded() {
        guard !didMigrateTestingTab else { return }
        if selectedTab == 1 {
            selectedTab = AppTab.settings.rawValue
        }
        didMigrateTestingTab = true
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
