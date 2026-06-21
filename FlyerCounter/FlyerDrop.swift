import CoreLocation
import Foundation

struct FlyerDrop: Identifiable, Codable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let timestamp: Date

    init(id: UUID = UUID(), latitude: Double, longitude: Double, timestamp: Date = Date()) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}