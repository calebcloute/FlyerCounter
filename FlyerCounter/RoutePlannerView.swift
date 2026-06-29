import CoreLocation
import MapKit
import SwiftUI

struct RoutePlannerView: View {
    @EnvironmentObject private var plannedRouteStore: PlannedRouteStore
    @EnvironmentObject private var areaBoundariesStore: AreaBoundariesStore
    @AppStorage("mapDisplayStyle") private var mapDisplayStyle = MapDisplayStyle.illustrated.rawValue

    var body: some View {
        NavigationStack {
            List {
                if let activeRoute = plannedRouteStore.activeRoute {
                    Section {
                        Label(activeRoute.name, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("\(activeRoute.pathPoints.count) path points · \(activeRoute.waypoints.count) waypoints")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Active Walking Plan")
                    } footer: {
                        Text("Used for planned-route auto counting and shown on the Route Tracking map.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Text("No active plan selected.")
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("Active Walking Plan")
                    } footer: {
                        Text("Choose a saved plan below or create a new one.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    if plannedRouteStore.routes.isEmpty {
                        Text("No saved walking plans yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(plannedRouteStore.routes) { route in
                            NavigationLink {
                                PlannedRouteDetailView(routeId: route.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(route.name)
                                            .fontWeight(.medium)
                                        if plannedRouteStore.activeRouteId == route.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                                .font(.caption)
                                        }
                                    }
                                    Text("\(route.waypoints.count) waypoints · \(route.pathPoints.count) path points")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete(perform: plannedRouteStore.deleteRoutes)
                    }
                } header: {
                    Text("Saved Plans")
                }
            }
            .navigationTitle("Route Planner")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        PlannedRouteEditorView()
                    } label: {
                        Label("New Plan", systemImage: "plus")
                    }
                }
            }
        }
    }
}

private struct PlannedRouteDetailView: View {
    @EnvironmentObject private var plannedRouteStore: PlannedRouteStore
    @EnvironmentObject private var areaBoundariesStore: AreaBoundariesStore
    @AppStorage("mapDisplayStyle") private var mapDisplayStyle = MapDisplayStyle.illustrated.rawValue

    let routeId: UUID
    @State private var cameraPosition: MapCameraPosition = .automatic

    private var route: PlannedWalkRoute? {
        plannedRouteStore.route(id: routeId)
    }

    var body: some View {
        Group {
            if let route {
                Map(position: $cameraPosition) {
                    if route.pathCoordinates.count >= 2 {
                        MapPolyline(coordinates: route.pathCoordinates)
                            .stroke(.green, lineWidth: 5)
                    }

                    ForEach(Array(route.waypointCoordinates.enumerated()), id: \.offset) { index, coordinate in
                        Annotation("", coordinate: coordinate, anchor: .center) {
                            Circle()
                                .fill(index == 0 ? .blue : .purple)
                                .frame(width: 12, height: 12)
                                .overlay(Circle().stroke(.white, lineWidth: 2))
                        }
                    }

                    if let boundaryId = route.boundaryId,
                       let boundary = areaBoundariesStore.boundary(id: boundaryId) {
                        OutsideBoundaryRing(coordinates: boundary.coordinates)
                    }
                }
                .mapStyle(selectedMapDisplayStyle.mapStyle)
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 12) {
                        Text(route.name)
                            .font(.headline)

                        Button {
                            plannedRouteStore.activeRouteId = route.id
                        } label: {
                            Label(
                                plannedRouteStore.activeRouteId == route.id ? "Active Plan" : "Use for Walking",
                                systemImage: plannedRouteStore.activeRouteId == route.id
                                    ? "checkmark.circle.fill"
                                    : "figure.walk"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(plannedRouteStore.activeRouteId == route.id)

                        Button(role: .destructive) {
                            plannedRouteStore.deleteRoute(id: route.id)
                        } label: {
                            Label("Delete Plan", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                }
                .navigationTitle(route.name)
                .navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    cameraPosition = .region(route.coordinateRegion)
                }
            } else {
                ContentUnavailableView("Plan Not Found", systemImage: "map")
            }
        }
    }

    private var selectedMapDisplayStyle: MapDisplayStyle {
        MapDisplayStyle(rawValue: mapDisplayStyle) ?? .illustrated
    }
}

struct PlannedRouteEditorView: View {
    @EnvironmentObject private var plannedRouteStore: PlannedRouteStore
    @EnvironmentObject private var areaBoundariesStore: AreaBoundariesStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("mapDisplayStyle") private var mapDisplayStyle = MapDisplayStyle.illustrated.rawValue
    @AppStorage("activeOverlayBoundaryId") private var activeOverlayBoundaryIdRaw = ""

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var waypoints: [DraftWaypoint] = []
    @State private var builtPath: [CLLocationCoordinate2D] = []
    @State private var isBuildingRoute = false
    @State private var buildErrorMessage: String?
    @State private var showNamingSheet = false
    @State private var routeName = ""

    private var overlayBoundaryId: UUID? {
        UUID(uuidString: activeOverlayBoundaryIdRaw)
    }

    var body: some View {
        MapReader { proxy in
            Map(position: $cameraPosition) {
                if builtPath.count >= 2 {
                    MapPolyline(coordinates: builtPath)
                        .stroke(.green, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                } else if waypoints.count >= 2 {
                    MapPolyline(coordinates: waypoints.map(\.coordinate))
                        .stroke(.gray, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 6]))
                }

                ForEach(Array(waypoints.enumerated()), id: \.element.id) { index, waypoint in
                    Annotation("", coordinate: waypoint.coordinate, anchor: .center) {
                        Circle()
                            .fill(index == 0 ? .blue : .purple)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }

                if let overlayBoundaryId,
                   let boundary = areaBoundariesStore.boundary(id: overlayBoundaryId) {
                    OutsideBoundaryRing(coordinates: boundary.coordinates)
                }
            }
            .mapStyle(selectedMapDisplayStyle.mapStyle)
            .onTapGesture { screenPoint in
                guard !isBuildingRoute,
                      let coordinate = proxy.convert(screenPoint, from: .local) else { return }
                waypoints.append(DraftWaypoint(coordinate: coordinate))
                builtPath = []
                buildErrorMessage = nil
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if isBuildingRoute {
                    ProgressView("Building walking route…")
                } else if let buildErrorMessage {
                    Text(buildErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                } else if builtPath.count >= 2 {
                    Text("Walking route ready. Tap Save to name this plan.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Tap the map to place waypoints, then build the walking route.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Button("Undo") {
                        undoLastWaypoint()
                    }
                    .buttonStyle(.bordered)
                    .disabled(waypoints.isEmpty || isBuildingRoute)

                    Button("Clear") {
                        clearDraft()
                    }
                    .buttonStyle(.bordered)
                    .disabled(waypoints.isEmpty || isBuildingRoute)

                    Button("Build Route") {
                        buildRoute()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(waypoints.count < 2 || isBuildingRoute)

                    Button("Save") {
                        routeName = ""
                        showNamingSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(builtPath.count < 2 || isBuildingRoute)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.ultraThinMaterial)
        }
        .navigationTitle("New Walking Plan")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showNamingSheet) {
            PlannedRouteNamingSheet(routeName: $routeName) {
                saveRoute()
            }
        }
    }

    private var selectedMapDisplayStyle: MapDisplayStyle {
        MapDisplayStyle(rawValue: mapDisplayStyle) ?? .illustrated
    }

    private func undoLastWaypoint() {
        guard !waypoints.isEmpty else { return }
        waypoints.removeLast()
        builtPath = []
        buildErrorMessage = nil
    }

    private func clearDraft() {
        waypoints.removeAll()
        builtPath = []
        buildErrorMessage = nil
    }

    private func buildRoute() {
        guard waypoints.count >= 2 else { return }

        isBuildingRoute = true
        buildErrorMessage = nil

        let coordinates = waypoints.map(\.coordinate)
        Task {
            do {
                let path = try await WalkRoutePlanner.buildWalkingPath(through: coordinates)
                builtPath = path
                cameraPosition = .region(MKCoordinateRegion(coordinates: path))
            } catch {
                buildErrorMessage = error.localizedDescription
                builtPath = []
            }
            isBuildingRoute = false
        }
    }

    private func saveRoute() {
        let trimmedName = routeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, builtPath.count >= 2, waypoints.count >= 2 else { return }

        let pathPoints = builtPath.map { StoredCoordinate(coordinate: $0) }
        let storedWaypoints = waypoints.map { StoredCoordinate(coordinate: $0.coordinate) }

        if let route = plannedRouteStore.addRoute(
            name: trimmedName,
            pathPoints: pathPoints,
            waypoints: storedWaypoints,
            boundaryId: overlayBoundaryId
        ) {
            plannedRouteStore.activeRouteId = route.id
            dismiss()
        }
    }
}

private struct DraftWaypoint: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

private struct PlannedRouteNamingSheet: View {
    @Binding var routeName: String
    @Environment(\.dismiss) private var dismiss
    let onSave: () -> Void

    private var trimmedName: String {
        routeName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Plan name", text: $routeName)
                        .textInputAutocapitalization(.words)
                }
            }
            .navigationTitle("Name Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave()
                        dismiss()
                    }
                    .disabled(trimmedName.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    RoutePlannerView()
        .environmentObject(PlannedRouteStore())
        .environmentObject(AreaBoundariesStore())
}
