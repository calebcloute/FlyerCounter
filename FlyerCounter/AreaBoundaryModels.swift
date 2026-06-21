import CoreGraphics
import CoreLocation
import Foundation
import MapKit

enum BoundaryOutlineStyle {
    /// Extra width drawn only outside the true boundary (meters).
    static let outsideThicknessMeters: Double = 40
}

struct AreaBoundary: Identifiable, Codable {
    let id: UUID
    var name: String
    var points: [StoredCoordinate]
    var createdAt: Date

    var coordinates: [CLLocationCoordinate2D] {
        points.map(\.coordinate)
    }

    var closedCoordinates: [CLLocationCoordinate2D] {
        guard let first = coordinates.first, coordinates.count >= 3 else { return coordinates }
        return coordinates + [first]
    }

    var coordinateRegion: MKCoordinateRegion {
        MKCoordinateRegion(coordinates: coordinates)
    }
}

enum AreaBoundaryStorage {
    private static let storageKey = "areaBoundaries"

    static func load() -> [AreaBoundary] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let boundaries = try? JSONDecoder().decode([AreaBoundary].self, from: data) else {
            return []
        }
        return boundaries.sorted { $0.createdAt > $1.createdAt }
    }

    static func save(_ boundaries: [AreaBoundary]) {
        guard let data = try? JSONEncoder().encode(boundaries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

extension MKCoordinateRegion {
    init(coordinates: [CLLocationCoordinate2D]) {
        guard !coordinates.isEmpty else {
            self = MKCoordinateRegion()
            return
        }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)
        let minLat = latitudes.min() ?? 0
        let maxLat = latitudes.max() ?? 0
        let minLon = longitudes.min() ?? 0
        let maxLon = longitudes.max() ?? 0

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let latitudeDelta = max((maxLat - minLat) * 1.4, 0.005)
        let longitudeDelta = max((maxLon - minLon) * 1.4, 0.005)

        self.init(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
        )
    }
}

enum PolygonOutwardOffset {
    static func offsetCoordinates(
        _ coordinates: [CLLocationCoordinate2D],
        distanceMeters: Double
    ) -> [CLLocationCoordinate2D] {
        guard coordinates.count >= 3, distanceMeters > 0 else { return coordinates }

        let origin = centroid(of: coordinates)
        let localPoints = coordinates.map { localMeters(from: $0, origin: origin) }
        let offsetLocal = offsetPolygon(points: localPoints, distance: distanceMeters)
        return offsetLocal.map { coordinate(from: $0, origin: origin) }
    }

    static func isCounterClockwise(_ coordinates: [CLLocationCoordinate2D]) -> Bool {
        guard coordinates.count >= 3 else { return true }
        let origin = centroid(of: coordinates)
        let local = coordinates.map { localMeters(from: $0, origin: origin) }
        return signedArea(local) > 0
    }

    private static func centroid(of coordinates: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
        let latitude = coordinates.map(\.latitude).reduce(0, +) / Double(coordinates.count)
        let longitude = coordinates.map(\.longitude).reduce(0, +) / Double(coordinates.count)
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private static func localMeters(
        from coordinate: CLLocationCoordinate2D,
        origin: CLLocationCoordinate2D
    ) -> CGPoint {
        let metersPerLatitude = 111_320.0
        let metersPerLongitude = 111_320.0 * cos(origin.latitude * .pi / 180)
        return CGPoint(
            x: (coordinate.longitude - origin.longitude) * metersPerLongitude,
            y: (coordinate.latitude - origin.latitude) * metersPerLatitude
        )
    }

    private static func coordinate(
        from point: CGPoint,
        origin: CLLocationCoordinate2D
    ) -> CLLocationCoordinate2D {
        let metersPerLatitude = 111_320.0
        let metersPerLongitude = 111_320.0 * cos(origin.latitude * .pi / 180)
        return CLLocationCoordinate2D(
            latitude: origin.latitude + Double(point.y) / metersPerLatitude,
            longitude: origin.longitude + Double(point.x) / metersPerLongitude
        )
    }

    private static func signedArea(_ points: [CGPoint]) -> Double {
        guard points.count >= 3 else { return 0 }

        var area = 0.0
        for index in points.indices {
            let next = (index + 1) % points.count
            area += Double(points[index].x * points[next].y - points[next].x * points[index].y)
        }
        return area / 2
    }

    private static func outwardNormal(from start: CGPoint, to end: CGPoint, isCCW: Bool) -> CGPoint {
        let deltaX = Double(end.x - start.x)
        let deltaY = Double(end.y - start.y)
        let length = hypot(deltaX, deltaY)
        guard length > 0 else { return .zero }

        if isCCW {
            return CGPoint(x: CGFloat(deltaY / length), y: CGFloat(-deltaX / length))
        }
        return CGPoint(x: CGFloat(-deltaY / length), y: CGFloat(deltaX / length))
    }

    private static func lineIntersection(
        _ lineAStart: CGPoint,
        _ lineAEnd: CGPoint,
        _ lineBStart: CGPoint,
        _ lineBEnd: CGPoint
    ) -> CGPoint? {
        let deltaAX = Double(lineAEnd.x - lineAStart.x)
        let deltaAY = Double(lineAEnd.y - lineAStart.y)
        let deltaBX = Double(lineBEnd.x - lineBStart.x)
        let deltaBY = Double(lineBEnd.y - lineBStart.y)
        let denominator = deltaAX * deltaBY - deltaAY * deltaBX
        guard abs(denominator) > 1e-9 else { return nil }

        let offsetX = Double(lineBStart.x - lineAStart.x)
        let offsetY = Double(lineBStart.y - lineAStart.y)
        let t = (offsetX * deltaBY - offsetY * deltaBX) / denominator
        return CGPoint(
            x: lineAStart.x + CGFloat(t * deltaAX),
            y: lineAStart.y + CGFloat(t * deltaAY)
        )
    }

    private static func offsetPolygon(points: [CGPoint], distance: Double) -> [CGPoint] {
        let count = points.count
        guard count >= 3 else { return points }

        let isCCW = signedArea(points) > 0
        var result: [CGPoint] = []
        result.reserveCapacity(count)

        for index in points.indices {
            let previous = points[(index - 1 + count) % count]
            let current = points[index]
            let next = points[(index + 1) % count]

            let normalIn = outwardNormal(from: previous, to: current, isCCW: isCCW)
            let normalOut = outwardNormal(from: current, to: next, isCCW: isCCW)

            let edgeInStart = offset(previous, by: normalIn, distance: distance)
            let edgeInEnd = offset(current, by: normalIn, distance: distance)
            let edgeOutStart = offset(current, by: normalOut, distance: distance)
            let edgeOutEnd = offset(next, by: normalOut, distance: distance)

            if let intersection = lineIntersection(edgeInStart, edgeInEnd, edgeOutStart, edgeOutEnd) {
                let miterLength = hypot(Double(intersection.x - current.x), Double(intersection.y - current.y))
                if miterLength <= distance * 4 {
                    result.append(intersection)
                    continue
                }
            }

            let averagedNormal = CGPoint(
                x: (normalIn.x + normalOut.x) / 2,
                y: (normalIn.y + normalOut.y) / 2
            )
            let averagedLength = hypot(Double(averagedNormal.x), Double(averagedNormal.y))
            if averagedLength > 0 {
                let scale = CGFloat(distance / averagedLength)
                result.append(
                    CGPoint(
                        x: current.x + averagedNormal.x * scale,
                        y: current.y + averagedNormal.y * scale
                    )
                )
            } else {
                result.append(offset(current, by: normalOut, distance: distance))
            }
        }

        return result
    }

    private static func offset(_ point: CGPoint, by normal: CGPoint, distance: Double) -> CGPoint {
        CGPoint(
            x: point.x + normal.x * CGFloat(distance),
            y: point.y + normal.y * CGFloat(distance)
        )
    }
}
