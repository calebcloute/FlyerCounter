import MapKit
import SwiftUI

enum MapDisplayStyle: String {
    case illustrated
    case satellite

    var mapStyle: MapStyle {
        switch self {
        case .illustrated:
            return .standard(elevation: .realistic)
        case .satellite:
            return .hybrid(elevation: .realistic)
        }
    }

    var toggleIcon: String {
        switch self {
        case .illustrated:
            return "globe.americas.fill"
        case .satellite:
            return "map"
        }
    }
}
