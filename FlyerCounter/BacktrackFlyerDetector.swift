import CoreLocation
import Foundation
import MapKit

struct BacktrackDetectionResult {
    let coordinate: CLLocationCoordinate2D
    let note: String
}

struct BacktrackEvaluation {
    let result: BacktrackDetectionResult?
    let statusMessage: String
}

struct BacktrackFlyerDetector {
    private var lastAutoCountDate: Date?
    private var outboundBearing: Double?
    private var outboundSamples = 0
    private var isReturning = false
    private var overlapDistance: CLLocationDistance = 0
    private var lastCountedOverlapAnchorIndex: Int?

    private let minimumOutboundSamples = 3
    private let recentPointSkipCount = 2
    private let oppositeBearingThreshold: Double = 90
    private let movementBearingLookback = 2

    mutating func reset() {
        lastAutoCountDate = nil
        outboundBearing = nil
        outboundSamples = 0
        isReturning = false
        overlapDistance = 0
        lastCountedOverlapAnchorIndex = nil
    }

    mutating func evaluate(
        routePoints: [StoredCoordinate],
        settings: BacktrackDetectionSettings,
        now: Date = Date()
    ) -> BacktrackEvaluation {
        guard routePoints.count >= 4 else {
            return BacktrackEvaluation(
                result: nil,
                statusMessage: "Need a few more GPS points"
            )
        }

        if let lastAutoCountDate,
           now.timeIntervalSince(lastAutoCountDate) < settings.cooldownSeconds {
            let remaining = Int(settings.cooldownSeconds - now.timeIntervalSince(lastAutoCountDate))
            return BacktrackEvaluation(
                result: nil,
                statusMessage: "Cooldown · \(max(1, remaining))s"
            )
        }

        let locations = routePoints.map {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude)
        }
        let currentIndex = locations.count - 1
        let current = locations[currentIndex]
        let previous = locations[currentIndex - 1]
        let stepDistance = current.distance(from: previous)

        guard stepDistance > 0 else {
            return BacktrackEvaluation(result: nil, statusMessage: "Waiting for movement")
        }

        let currentBearing = previous.bearing(to: current)

        if !isReturning {
            trackOutboundBearing(currentBearing)

            if let outboundBearing,
               outboundSamples >= minimumOutboundSamples,
               let recentBearing = movementBearing(
                   locations: locations,
                   endIndex: currentIndex,
                   lookback: movementBearingLookback
               ),
               bearingDifference(recentBearing, outboundBearing) >= oppositeBearingThreshold {
                isReturning = true
                if isOverlappingOutboundPath(
                    locations: locations,
                    currentIndex: currentIndex,
                    tolerance: settings.pathMatchToleranceMeters
                ) {
                    overlapDistance = stepDistance
                }
            } else {
                let bearingText = outboundBearing.map { "\(Int($0))°" } ?? "—"
                return BacktrackEvaluation(
                    result: nil,
                    statusMessage: "Outbound · heading \(bearingText)"
                )
            }
        }

        if isOverlappingOutboundPath(
            locations: locations,
            currentIndex: currentIndex,
            tolerance: settings.pathMatchToleranceMeters
        ) {
            overlapDistance += stepDistance
        }

        guard overlapDistance >= settings.minimumOverlapMeters else {
            return BacktrackEvaluation(
                result: nil,
                statusMessage: "Returning · \(Int(overlapDistance))/\(Int(settings.minimumOverlapMeters)) m overlap"
            )
        }

        let anchorIndex = nearestOutboundAnchorIndex(
            locations: locations,
            currentIndex: currentIndex,
            tolerance: settings.pathMatchToleranceMeters
        )

        if let anchorIndex, anchorIndex == lastCountedOverlapAnchorIndex {
            return BacktrackEvaluation(
                result: nil,
                statusMessage: "Returning · overlap matched, waiting for new spot"
            )
        }

        let countedOverlap = overlapDistance
        lastAutoCountDate = now
        lastCountedOverlapAnchorIndex = anchorIndex
        resetLegState()

        return BacktrackEvaluation(
            result: BacktrackDetectionResult(
                coordinate: current.coordinate,
                note: "Backtrack · \(Int(countedOverlap)) m overlap"
            ),
            statusMessage: "Counted · \(Int(countedOverlap)) m overlap"
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

    private mutating func resetLegState() {
        isReturning = false
        overlapDistance = 0
        outboundBearing = nil
        outboundSamples = 0
    }

    private func isOverlappingOutboundPath(
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

        var bestIndex: Int?
        var bestDistance = CLLocationDistance.infinity

        if searchEnd >= 2 {
            for index in 0..<(searchEnd - 1) {
                let distance = segmentDistance(
                    from: current,
                    segmentStart: locations[index],
                    segmentEnd: locations[index + 1]
                )
                if distance <= tolerance, distance < bestDistance {
                    bestDistance = distance
                    bestIndex = index
                }
            }
        }

        for index in 0..<searchEnd {
            let distance = current.distance(from: locations[index])
            if distance <= tolerance, distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }

        return bestIndex
    }

    private func movementBearing(
        locations: [CLLocation],
        endIndex: Int,
        lookback: Int
    ) -> Double? {
        let startIndex = endIndex - lookback
        guard startIndex >= 0 else { return nil }

        let start = locations[startIndex]
        let end = locations[endIndex]
        guard start.distance(from: end) >= 1 else { return nil }

        return start.bearing(to: end)
    }

    private func segmentDistance(
        from location: CLLocation,
        segmentStart: CLLocation,
        segmentEnd: CLLocation
    ) -> CLLocationDistance {
        let start = MKMapPoint(segmentStart.coordinate)
        let end = MKMapPoint(segmentEnd.coordinate)
        let point = MKMapPoint(location.coordinate)

        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let lengthSquared = deltaX * deltaX + deltaY * deltaY
        guard lengthSquared > 0 else {
            return location.distance(from: segmentStart)
        }

        let projection = max(
            0,
            min(1, ((point.x - start.x) * deltaX + (point.y - start.y) * deltaY) / lengthSquared)
        )
        let closest = MKMapPoint(x: start.x + projection * deltaX, y: start.y + projection * deltaY)
        return location.distance(
            from: CLLocation(latitude: closest.coordinate.latitude, longitude: closest.coordinate.longitude)
        )
    }

    private func averagedBearing(_ lhs: Double, _ rhs: Double) -> Double {
        let lhsX = cos(lhs * .pi / 180)
        let lhsY = sin(lhs * .pi / 180)
        let rhsX = cos(rhs * .pi / 180)
        let rhsY = sin(rhs * .pi / 180)
        let sumX = lhsX + rhsX
        let sumY = lhsY + rhsY
        guard sumX != 0 || sumY != 0 else { return lhs }
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
