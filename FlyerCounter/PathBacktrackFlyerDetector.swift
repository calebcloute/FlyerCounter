import CoreLocation
import Foundation

struct PathBacktrackFlyerDetector {
    private var furthestAlongPathMeters: CLLocationDistance = 0
    private var lastCountedAlongPathMeters: CLLocationDistance?
    private var lastAutoCountDate: Date?

    mutating func reset() {
        furthestAlongPathMeters = 0
        lastCountedAlongPathMeters = nil
        lastAutoCountDate = nil
    }

    mutating func beginRouteSession(at date: Date = Date()) {
        reset()
        lastAutoCountDate = date
    }

    mutating func evaluate(
        location: CLLocation,
        routePoints: [StoredCoordinate],
        settings: PathBacktrackSettings,
        now: Date = Date()
    ) -> AutoFlyerEvaluation {
        let coordinates = routePoints.map(\.coordinate)

        guard coordinates.count >= 4 else {
            return AutoFlyerEvaluation(
                result: nil,
                statusMessage: "Walking path · need more route points"
            )
        }

        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= settings.maximumGPSAccuracyMeters else {
            return AutoFlyerEvaluation(result: nil, statusMessage: "Waiting for GPS accuracy")
        }

        if let cooldownRemaining = cooldownRemainingSeconds(now: now, settings: settings) {
            return AutoFlyerEvaluation(
                result: nil,
                statusMessage: "Path backtrack · cooldown \(cooldownRemaining)s",
                cooldownRemainingSeconds: cooldownRemaining
            )
        }

        guard let onPath = BoundaryProximity.locateOnPolyline(from: location, polyline: coordinates) else {
            return AutoFlyerEvaluation(result: nil, statusMessage: "Walking path · no path yet")
        }

        let overlapRadius = min(
            settings.overlapRadiusMeters,
            max(location.horizontalAccuracy * 0.75, 3)
        )

        guard onPath.distanceFromLocation <= overlapRadius else {
            return AutoFlyerEvaluation(
                result: nil,
                statusMessage:
                    "Walking path · \(Int(onPath.distanceFromLocation)) m from line " +
                    "(need within \(Int(overlapRadius)) m)"
            )
        }

        furthestAlongPathMeters = max(furthestAlongPathMeters, onPath.distanceAlongPolyline)

        let pathBehindFurthest = furthestAlongPathMeters - onPath.distanceAlongPolyline
        guard pathBehindFurthest >= settings.minBacktrackSeparationMeters else {
            return AutoFlyerEvaluation(
                result: nil,
                statusMessage:
                    "Walking path · furthest \(Int(furthestAlongPathMeters)) m along line · " +
                    "need \(Int(settings.minBacktrackSeparationMeters)) m back to count"
            )
        }

        if let lastCountedAlongPathMeters,
           abs(onPath.distanceAlongPolyline - lastCountedAlongPathMeters) < overlapRadius {
            return AutoFlyerEvaluation(
                result: nil,
                statusMessage: "Walking path · already counted this overlap"
            )
        }

        guard let countCoordinate = BoundaryProximity.coordinateAlongPolyline(
            atDistance: furthestAlongPathMeters,
            polyline: coordinates
        ) else {
            return AutoFlyerEvaluation(result: nil, statusMessage: "Walking path · could not place count")
        }

        lastAutoCountDate = now
        lastCountedAlongPathMeters = onPath.distanceAlongPolyline
        furthestAlongPathMeters = onPath.distanceAlongPolyline

        return AutoFlyerEvaluation(
            result: AutoFlyerDetectionResult(
                coordinate: countCoordinate,
                note: "Backtrack · \(Int(pathBehindFurthest)) m back along path"
            ),
            statusMessage: "Counted · backtrack at furthest point",
            countedBacktrackOverlap: true
        )
    }

    private func cooldownRemainingSeconds(now: Date, settings: PathBacktrackSettings) -> Int? {
        guard let lastAutoCountDate,
              now.timeIntervalSince(lastAutoCountDate) < settings.cooldownSeconds else {
            return nil
        }

        let remaining = Int(settings.cooldownSeconds - now.timeIntervalSince(lastAutoCountDate))
        return max(1, remaining)
    }
}
