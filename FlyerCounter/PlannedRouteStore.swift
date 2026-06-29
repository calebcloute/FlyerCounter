import Combine
import Foundation
import SwiftUI

@MainActor
final class PlannedRouteStore: ObservableObject {
    @Published private(set) var routes: [PlannedWalkRoute] = []
    @Published var activeRouteId: UUID? {
        didSet {
            let raw = activeRouteId?.uuidString ?? ""
            if UserDefaults.standard.string(forKey: Self.activeRouteStorageKey) != raw {
                UserDefaults.standard.set(raw, forKey: Self.activeRouteStorageKey)
            }
        }
    }

    private static let activeRouteStorageKey = "activePlannedWalkRouteId"

    init() {
        routes = PlannedWalkRouteStorage.load()
        if let raw = UserDefaults.standard.string(forKey: Self.activeRouteStorageKey),
           let id = UUID(uuidString: raw),
           routes.contains(where: { $0.id == id }) {
            activeRouteId = id
        }
    }

    var activeRoute: PlannedWalkRoute? {
        guard let activeRouteId else { return nil }
        return routes.first { $0.id == activeRouteId }
    }

    func route(id: UUID) -> PlannedWalkRoute? {
        routes.first { $0.id == id }
    }

    @discardableResult
    func addRoute(
        name: String,
        pathPoints: [StoredCoordinate],
        waypoints: [StoredCoordinate],
        boundaryId: UUID?
    ) -> PlannedWalkRoute? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, pathPoints.count >= 2, waypoints.count >= 2 else { return nil }

        let route = PlannedWalkRoute(
            id: UUID(),
            name: trimmedName,
            pathPoints: pathPoints,
            waypoints: waypoints,
            boundaryId: boundaryId,
            createdAt: Date()
        )
        routes.insert(route, at: 0)
        PlannedWalkRouteStorage.save(routes)
        return route
    }

    func deleteRoutes(at offsets: IndexSet) {
        let removedIds = offsets.map { routes[$0].id }
        routes.remove(atOffsets: offsets)
        if let activeRouteId, removedIds.contains(activeRouteId) {
            self.activeRouteId = nil
        }
        PlannedWalkRouteStorage.save(routes)
    }

    func deleteRoute(id: UUID) {
        routes.removeAll { $0.id == id }
        if activeRouteId == id {
            activeRouteId = nil
        }
        PlannedWalkRouteStorage.save(routes)
    }
}
