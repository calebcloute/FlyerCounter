import CoreLocation
import Foundation
import MapKit

struct PlannedWalkRoute: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    /// Dense walking polyline from MapKit directions.
    var pathPoints: [StoredCoordinate]
    /// Original tap points used to request directions.
    var waypoints: [StoredCoordinate]
    var boundaryId: UUID?
    var createdAt: Date

    var pathCoordinates: [CLLocationCoordinate2D] {
        pathPoints.map(\.coordinate)
    }

    var waypointCoordinates: [CLLocationCoordinate2D] {
        waypoints.map(\.coordinate)
    }

    var coordinateRegion: MKCoordinateRegion {
        MKCoordinateRegion(coordinates: pathCoordinates.isEmpty ? waypointCoordinates : pathCoordinates)
    }
}

enum PlannedWalkRouteStorage {
    private static let storageKey = "plannedWalkRoutes"

    static func load() -> [PlannedWalkRoute] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let routes = try? JSONDecoder().decode([PlannedWalkRoute].self, from: data) else {
            return []
        }
        return routes.sorted { $0.createdAt > $1.createdAt }
    }

    static func save(_ routes: [PlannedWalkRoute]) {
        guard let data = try? JSONEncoder().encode(routes) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

enum WalkRoutePlanner {
    enum PlannerError: LocalizedError {
        case notEnoughWaypoints
        case routingFailed

        var errorDescription: String? {
            switch self {
            case .notEnoughWaypoints:
                "Add at least two waypoints on the map."
            case .routingFailed:
                "Could not build a walking route between those points."
            }
        }
    }

    static func buildWalkingPath(through waypoints: [CLLocationCoordinate2D]) async throws -> [CLLocationCoordinate2D] {
        guard waypoints.count >= 2 else { throw PlannerError.notEnoughWaypoints }

        var merged: [CLLocationCoordinate2D] = []

        for index in 0..<(waypoints.count - 1) {
            let segment = try await routeSegment(from: waypoints[index], to: waypoints[index + 1])
            if let last = merged.last,
               let first = segment.first,
               last.latitude == first.latitude,
               last.longitude == first.longitude {
                merged.append(contentsOf: segment.dropFirst())
            } else {
                merged.append(contentsOf: segment)
            }
        }

        guard merged.count >= 2 else { throw PlannerError.routingFailed }
        return merged
    }

    private static func routeSegment(
        from source: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D
    ) async throws -> [CLLocationCoordinate2D] {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = .walking
        request.requestsAlternateRoutes = false

        let directions = MKDirections(request: request)
        let response = try await directions.calculate()

        guard let route = response.routes.first else { throw PlannerError.routingFailed }

        let polyline = route.polyline
        let count = polyline.pointCount
        guard count >= 2 else { throw PlannerError.routingFailed }

        var coordinates = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: count)
        polyline.getCoordinates(&coordinates, range: NSRange(location: 0, length: count))
        return coordinates
    }
}
