import AudioToolbox
import CoreLocation
import MapKit

enum BoundaryProximity {
    /// Whether the user is on the boundary edge or outside the area (not merely approaching).
    static func shouldAlert(
        location: CLLocation,
        polygon: [CLLocationCoordinate2D],
        settings: BoundaryAlertSettings
    ) -> Bool {
        guard polygon.count >= 2 else { return false }

        let edgeDistance = nearestDistance(from: location, toClosedPolygon: polygon)
        let onBoundaryMeters = onBoundaryThreshold(for: location, settings: settings)

        if polygon.count >= 3 {
            let inside = contains(location.coordinate, in: polygon)
            if !inside {
                return true
            }
            return edgeDistance <= onBoundaryMeters
        }

        return edgeDistance <= onBoundaryMeters
    }

    static func isSafelyInside(
        location: CLLocation,
        polygon: [CLLocationCoordinate2D],
        settings: BoundaryAlertSettings
    ) -> Bool {
        guard polygon.count >= 3 else { return false }
        guard contains(location.coordinate, in: polygon) else { return false }

        let edgeDistance = nearestDistance(from: location, toClosedPolygon: polygon)
        return edgeDistance > onBoundaryThreshold(for: location, settings: settings)
    }

    static func playVibrationPulsePair() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }

    static func nearestDistance(
        from location: CLLocation,
        toPolyline coordinates: [CLLocationCoordinate2D]
    ) -> CLLocationDistance {
        locateOnPolyline(from: location, polyline: coordinates)?.distanceFromLocation ?? .infinity
    }

    struct PolylineLocation {
        let distanceFromLocation: CLLocationDistance
        let distanceAlongPolyline: CLLocationDistance
        let closestCoordinate: CLLocationCoordinate2D
    }

    static func locateOnPolyline(
        from location: CLLocation,
        polyline coordinates: [CLLocationCoordinate2D]
    ) -> PolylineLocation? {
        guard let first = coordinates.first else { return nil }

        guard coordinates.count >= 2 else {
            let point = CLLocation(latitude: first.latitude, longitude: first.longitude)
            return PolylineLocation(
                distanceFromLocation: location.distance(from: point),
                distanceAlongPolyline: 0,
                closestCoordinate: first
            )
        }

        var bestDistance = CLLocationDistance.infinity
        var bestAlongPolyline: CLLocationDistance = 0
        var bestCoordinate = first
        var traversed: CLLocationDistance = 0

        for index in 0..<(coordinates.count - 1) {
            let start = coordinates[index]
            let end = coordinates[index + 1]
            let proximity = segmentProximity(from: location, segmentStart: start, segmentEnd: end)

            if proximity.distance < bestDistance {
                bestDistance = proximity.distance
                bestAlongPolyline = traversed + proximity.segmentLength * proximity.projection
                bestCoordinate = proximity.closestCoordinate
            }

            traversed += proximity.segmentLength
        }

        return PolylineLocation(
            distanceFromLocation: bestDistance,
            distanceAlongPolyline: bestAlongPolyline,
            closestCoordinate: bestCoordinate
        )
    }

    static func totalPolylineLength(_ coordinates: [CLLocationCoordinate2D]) -> CLLocationDistance {
        guard coordinates.count >= 2 else { return 0 }

        var total: CLLocationDistance = 0
        for index in 0..<(coordinates.count - 1) {
            let start = coordinates[index]
            let end = coordinates[index + 1]
            total += CLLocation(latitude: start.latitude, longitude: start.longitude)
                .distance(from: CLLocation(latitude: end.latitude, longitude: end.longitude))
        }
        return total
    }

    static func coordinateAlongPolyline(
        atDistance distance: CLLocationDistance,
        polyline coordinates: [CLLocationCoordinate2D]
    ) -> CLLocationCoordinate2D? {
        guard let first = coordinates.first else { return nil }
        guard coordinates.count >= 2 else { return first }

        let target = max(0, distance)
        var traversed: CLLocationDistance = 0

        for index in 0..<(coordinates.count - 1) {
            let start = coordinates[index]
            let end = coordinates[index + 1]
            let startLocation = CLLocation(latitude: start.latitude, longitude: start.longitude)
            let endLocation = CLLocation(latitude: end.latitude, longitude: end.longitude)
            let segmentLength = startLocation.distance(from: endLocation)
            guard segmentLength > 0 else { continue }

            if traversed + segmentLength >= target {
                let remaining = target - traversed
                let fraction = remaining / segmentLength
                let latitude = start.latitude + (end.latitude - start.latitude) * fraction
                let longitude = start.longitude + (end.longitude - start.longitude) * fraction
                return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            }

            traversed += segmentLength
        }

        return coordinates.last
    }

    static func nearestDistance(
        from location: CLLocation,
        toClosedPolygon coordinates: [CLLocationCoordinate2D]
    ) -> CLLocationDistance {
        guard let first = coordinates.first else { return .infinity }
        guard coordinates.count >= 2 else {
            return location.distance(from: CLLocation(latitude: first.latitude, longitude: first.longitude))
        }

        var minimum = CLLocationDistance.infinity
        for index in coordinates.indices {
            let next = (index + 1) % coordinates.count
            let segmentDistance = distance(
                from: location,
                segmentStart: coordinates[index],
                segmentEnd: coordinates[next]
            )
            minimum = min(minimum, segmentDistance)
        }
        return minimum
    }

    private static func onBoundaryThreshold(
        for location: CLLocation,
        settings: BoundaryAlertSettings
    ) -> CLLocationDistance {
        let configured = max(2, settings.edgeThresholdMeters)
        guard location.horizontalAccuracy >= 0 else { return configured }

        let accuracyLimit = max(location.horizontalAccuracy * 0.5, 2)
        return min(configured, accuracyLimit)
    }

    private static func contains(
        _ coordinate: CLLocationCoordinate2D,
        in polygon: [CLLocationCoordinate2D]
    ) -> Bool {
        guard polygon.count >= 3 else { return false }

        var inside = false
        var previousIndex = polygon.count - 1

        for index in polygon.indices {
            let current = polygon[index]
            let previous = polygon[previousIndex]

            let latitudeCrossed = (current.latitude > coordinate.latitude)
                != (previous.latitude > coordinate.latitude)
            if latitudeCrossed {
                let longitudeAtLatitude = (previous.longitude - current.longitude)
                    * (coordinate.latitude - current.latitude)
                    / (previous.latitude - current.latitude)
                    + current.longitude
                if coordinate.longitude < longitudeAtLatitude {
                    inside.toggle()
                }
            }
            previousIndex = index
        }

        return inside
    }

    private struct SegmentProximity {
        let distance: CLLocationDistance
        let projection: Double
        let segmentLength: CLLocationDistance
        let closestCoordinate: CLLocationCoordinate2D
    }

    private static func segmentProximity(
        from location: CLLocation,
        segmentStart: CLLocationCoordinate2D,
        segmentEnd: CLLocationCoordinate2D
    ) -> SegmentProximity {
        let start = MKMapPoint(segmentStart)
        let end = MKMapPoint(segmentEnd)
        let point = MKMapPoint(location.coordinate)

        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let lengthSquared = deltaX * deltaX + deltaY * deltaY
        let segmentLength = sqrt(lengthSquared)

        guard lengthSquared > 0 else {
            return SegmentProximity(
                distance: location.distance(
                    from: CLLocation(latitude: segmentStart.latitude, longitude: segmentStart.longitude)
                ),
                projection: 0,
                segmentLength: 0,
                closestCoordinate: segmentStart
            )
        }

        let projection = max(
            0,
            min(1, ((point.x - start.x) * deltaX + (point.y - start.y) * deltaY) / lengthSquared)
        )
        let closest = MKMapPoint(x: start.x + projection * deltaX, y: start.y + projection * deltaY)
        let closestCoordinate = closest.coordinate
        let distance = location.distance(
            from: CLLocation(latitude: closestCoordinate.latitude, longitude: closestCoordinate.longitude)
        )

        return SegmentProximity(
            distance: distance,
            projection: projection,
            segmentLength: segmentLength,
            closestCoordinate: closestCoordinate
        )
    }

    private static func distance(
        from location: CLLocation,
        segmentStart: CLLocationCoordinate2D,
        segmentEnd: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        segmentProximity(from: location, segmentStart: segmentStart, segmentEnd: segmentEnd).distance
    }
}
