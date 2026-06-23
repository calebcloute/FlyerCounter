import CoreLocation
import Foundation

enum FlyerDropSource: String, Codable {
    case manual
    case autoBacktrack
}

struct FlyerDrop: Identifiable, Codable {
    let id: UUID
    let latitude: Double
    let longitude: Double
    let timestamp: Date
    let source: FlyerDropSource?

    init(
        id: UUID = UUID(),
        latitude: Double,
        longitude: Double,
        timestamp: Date = Date(),
        source: FlyerDropSource? = .manual
    ) {
        self.id = id
        self.latitude = latitude
        self.longitude = longitude
        self.timestamp = timestamp
        self.source = source
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var resolvedSource: FlyerDropSource {
        source ?? .manual
    }

    enum CodingKeys: String, CodingKey {
        case id
        case latitude
        case longitude
        case timestamp
        case source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        source = try container.decodeIfPresent(FlyerDropSource.self, forKey: .source)
    }
}