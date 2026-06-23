import CoreLocation
import Foundation

struct BacktrackDetectionResult {
    let coordinate: CLLocationCoordinate2D
    let note: String
}

struct BacktrackFlyerDetector {
    private var lastAutoCountDate: Date?
    private var outboundBearing: Double?
    private var outboundSamples = 0
    private var isReturning = false
    private var returningDistance: CLLocationDistance = 0
    private var overlapDistance: CLLocationDistance = 0
    private var lastCountedOverlapAnchorIndex: Int?

    private let minimumOutboundSamples = 3
    private let recentPointSkipCount = 5
    private let oppositeBearingThreshold: Double = 115

    mutating func reset() {
        lastAutoCountDate = nil
        outboundBearing = nil
        outboundSamples = 0
        isReturning = false
        returningDistance = 0
        overlapDistance = 0
        lastCountedOverlapAnchorIndex = nil
    }

    mutating func evaluate(
        routePoints: [StoredCoordinate],
        settings: BacktrackDetectionSettings,
        now: Date = Date()
    ) -> BacktrackDetectionResult? {
        guard routePoints.count >= 4 else { return nil }

        if let lastAutoCountDate,
           now.timeIntervalSince(lastAutoCountDate) < settings.cooldownSeconds {
            return nil
        }

        let locations = routePoints.map {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude)
        }
        let currentIndex = locations.count - 1
        let current = locations[currentIndex]
        let previous = locations[currentIndex - 1]
        let stepDistance = current.distance(from: previous)

        guard stepDistance > 0 else { return nil }

        let currentBearing = previous.bearing(to: current)

        if !isReturning {
            trackOutboundBearing(currentBearing)

            if let outboundBearing,
               outboundSamples >= minimumOutboundSamples,
               bearingDifference(currentBearing, outboundBearing) >= oppositeBearingThreshold {
                isReturning = true
                returningDistance = stepDistance
                overlapDistance = overlapForCurrentPoint(
                    locations: locations,
                    currentIndex: currentIndex,
                    tolerance: settings.pathMatchToleranceMeters
                ) ? stepDistance : 0
            }
            return nil
        }

        returningDistance += stepDistance

        if overlapForCurrentPoint(
            locations: locations,
            currentIndex: currentIndex,
            tolerance: settings.pathMatchToleranceMeters
        ) {
            overlapDistance += stepDistance
        }

        guard returningDistance >= settings.minimumReverseDistanceMeters,
              overlapDistance >= settings.minimumOverlapMeters else {
            return nil
        }

        let anchorIndex = nearestOutboundAnchorIndex(
            locations: locations,
            currentIndex: currentIndex,
            tolerance: settings.pathMatchToleranceMeters
        )

        if let anchorIndex, anchorIndex == lastCountedOverlapAnchorIndex {
            return nil
        }

        lastAutoCountDate = now
        lastCountedOverlapAnchorIndex = anchorIndex
        resetReturningState()

        return BacktrackDetectionResult(
            coordinate: current.coordinate,
            note: "Backtrack · \(Int(overlapDistance)) m overlap"
        )
    }

    private mutating func trackOutboundBearing(_ bearing: Double) {
        outboundSamples += 1

        if let outboundBearing {
            self.outboundBearing = averagedBearing(outboundBearing, bearing)
        } else {
            outboundBearing = bearing
        }
    }

    private mutating func resetReturningState() {
        isReturning = false
        returningDistance = 0
        overlapDistance = 0
    }

    private func overlapForCurrentPoint(
        locations: [CLLocation],
        currentIndex: Int,
        tolerance: CLLocationDistance
    ) -> Bool {
        nearestOutboundAnchorIndex(
            locations: locations,
            currentIndex: currentIndex,
            tolerance: tolerance
        ) != nil
    }

    private func nearestOutboundAnchorIndex(
        locations: [CLLocation],
        currentIndex: Int,
        tolerance: CLLocationDistance
    ) -> Int? {
        let current = locations[currentIndex]
        let searchEnd = max(0, currentIndex - recentPointSkipCount)
        guard searchEnd > minimumOutboundSamples else { return nil }

        for index in 0..<searchEnd {
            if locations[index].distance(from: current) <= tolerance {
                return index
            }
        }
        return nil
    }

    private func averagedBearing(_ lhs: Double, _ rhs: Double) -> Double {
        let lhsX = cos(lhs * .pi / 180)
        let lhsY = sin(lhs * .pi / 180)
        let rhsX = cos(rhs * .pi / 180)
        let rhsY = sin(rhs * .pi / 180)
        let sumX = lhsX + rhsX
        let sumY = lhsY + rhsY
        let averaged = atan2(sumY, sumX) * 180 / .pi
        return (averaged + 360).truncatingRemainder(dividingBy: 360)
    }

    private func bearingDifference(_ lhs: Double, _ rhs: Double) -> Double {
        let difference = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return difference > 180 ? 360 - difference : difference
    }
}

private extension CLLocation {
    func bearing(to destination: CLLocation) -> Double {
        let lat1 = coordinate.latitude * .pi / 180
        let lat2 = destination.coordinate.latitude * .pi / 180
        let deltaLon = (destination.coordinate.longitude - coordinate.longitude) * .pi / 180

        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        let bearing = atan2(y, x) * 180 / .pi
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }
}
