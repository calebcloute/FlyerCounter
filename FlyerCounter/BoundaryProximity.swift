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

    private static func distance(
        from location: CLLocation,
        segmentStart: CLLocationCoordinate2D,
        segmentEnd: CLLocationCoordinate2D
    ) -> CLLocationDistance {
        let start = MKMapPoint(segmentStart)
        let end = MKMapPoint(segmentEnd)
        let point = MKMapPoint(location.coordinate)

        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let lengthSquared = deltaX * deltaX + deltaY * deltaY
        guard lengthSquared > 0 else {
            return location.distance(
                from: CLLocation(latitude: segmentStart.latitude, longitude: segmentStart.longitude)
            )
        }

        let projection = max(
            0,
            min(1, ((point.x - start.x) * deltaX + (point.y - start.y) * deltaY) / lengthSquared)
        )
        let closest = MKMapPoint(x: start.x + projection * deltaX, y: start.y + projection * deltaY)
        let closestCoordinate = closest.coordinate
        return location.distance(
            from: CLLocation(latitude: closestCoordinate.latitude, longitude: closestCoordinate.longitude)
        )
    }
}
