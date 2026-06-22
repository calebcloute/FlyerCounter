import SwiftUI

private enum AppTab: Int {
    case routeTracking = 0
    case preferences = 1
}

struct ContentView: View {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var routeMethodsStore = RouteMethodsStore()
    @StateObject private var neighborhoodTypesStore = NeighborhoodTypesStore()
    @StateObject private var areaBoundariesStore = AreaBoundariesStore()

    @AppStorage("selectedTab") private var selectedTab = AppTab.routeTracking.rawValue
    @AppStorage("activeOverlayBoundaryId") private var activeOverlayBoundaryIdRaw = ""
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

            PreferencesView()
                .tabItem {
                    Label("Preferences", systemImage: "gearshape")
                }
                .tag(AppTab.preferences.rawValue)
        }
        .environmentObject(routeMethodsStore)
        .environmentObject(neighborhoodTypesStore)
        .environmentObject(areaBoundariesStore)
        .onAppear {
            migrateSelectedTabIfNeeded()
            locationManager.prepareForUse()
            syncActiveBoundaryOverlay()
            showRouteTrackingForPausedNamingIfNeeded()
        }
        .onChange(of: activeOverlayBoundaryIdRaw) { _, _ in
            syncActiveBoundaryOverlay()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                locationManager.prepareForUse()
                syncActiveBoundaryOverlay()
                showRouteTrackingForPausedNamingIfNeeded()
            }
        }
    }

    private func migrateSelectedTabIfNeeded() {
        switch selectedTab {
        case 1:
            selectedTab = AppTab.routeTracking.rawValue
        case 2:
            selectedTab = AppTab.preferences.rawValue
        default:
            break
        }
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
