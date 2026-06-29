import CoreLocation
import Foundation

struct PlannedRouteDivergenceFlyerDetector {
    private var wasNearPlan = false
    private var lastAutoCountDate: Date?

    mutating func reset() {
        wasNearPlan = false
        lastAutoCountDate = nil
    }

    mutating func beginRouteSession(at date: Date = Date()) {
        reset()
        lastAutoCountDate = date
    }

    mutating func evaluate(
        location: CLLocation,
        planCoordinates: [CLLocationCoordinate2D],
        settings: PlannedRouteDetectionSettings,
        now: Date = Date()
    ) -> AutoFlyerEvaluation {
        guard planCoordinates.count >= 2 else {
            return AutoFlyerEvaluation(
                result: nil,
                statusMessage: "No active walking plan"
            )
        }

        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= settings.maximumGPSAccuracyMeters else {
            return AutoFlyerEvaluation(result: nil, statusMessage: "Waiting for GPS accuracy")
        }

        if let cooldownRemaining = cooldownRemainingSeconds(now: now, settings: settings) {
            return AutoFlyerEvaluation(
                result: nil,
                statusMessage: "On plan · cooldown \(cooldownRemaining)s",
                cooldownRemainingSeconds: cooldownRemaining
            )
        }

        let distance = BoundaryProximity.nearestDistance(from: location, toPolyline: planCoordinates)
        let nearLimit = min(settings.nearPlanMeters, effectiveAccuracyLimit(for: location, settings: settings))
        let divergeLimit = max(
            settings.divergenceThresholdMeters,
            nearLimit + 2
        )

        if distance <= nearLimit {
            wasNearPlan = true
        }

        let statusMessage =
            "Plan distance \(Int(distance)) m · need \(Int(divergeLimit)) m " +
            "(near \(Int(nearLimit)) m)"

        guard wasNearPlan, distance >= divergeLimit else {
            return AutoFlyerEvaluation(result: nil, statusMessage: statusMessage)
        }

        wasNearPlan = false
        lastAutoCountDate = now

        return AutoFlyerEvaluation(
            result: AutoFlyerDetectionResult(
                coordinate: location.coordinate,
                note: "Plan · \(Int(distance)) m off path"
            ),
            statusMessage: "Counted · \(Int(distance)) m off plan",
            countedMetersFromPlan: Int(distance)
        )
    }

    private func cooldownRemainingSeconds(now: Date, settings: PlannedRouteDetectionSettings) -> Int? {
        guard let lastAutoCountDate,
              now.timeIntervalSince(lastAutoCountDate) < settings.cooldownSeconds else {
            return nil
        }

        let remaining = Int(settings.cooldownSeconds - now.timeIntervalSince(lastAutoCountDate))
        return max(1, remaining)
    }

    private func effectiveAccuracyLimit(
        for location: CLLocation,
        settings: PlannedRouteDetectionSettings
    ) -> CLLocationDistance {
        min(settings.maximumGPSAccuracyMeters, max(location.horizontalAccuracy * 0.75, 5))
    }
}
