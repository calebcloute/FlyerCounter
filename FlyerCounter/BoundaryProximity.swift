import AudioToolbox
import CoreLocation
import MapKit
import UIKit

enum BoundaryProximity {
    static let alertDistanceMeters: CLLocationDistance = 50
    static let resetDistanceMeters: CLLocationDistance = 55
    static let maximumLocationAccuracy: CLLocationAccuracy = 40

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

    static func playNearbyAlert() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)

        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.warning)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            generator.notificationOccurred(.warning)
        }
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
