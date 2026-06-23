import CoreLocation
import Foundation

struct CompassTurnaroundFlyerDetector {
    private struct HeadingSample {
        let date: Date
        let heading: Double
    }

    private var headingHistory: [HeadingSample] = []
    private var lastAutoCountDate: Date?

    private let directionLookbackSeconds: TimeInterval = 3
    private let historyRetentionSeconds: TimeInterval = 30

    mutating func reset() {
        headingHistory = []
        lastAutoCountDate = nil
    }

    mutating func evaluate(
        travelHeading: Double?,
        settings: CompassTurnaroundSettings,
        now: Date = Date()
    ) -> BacktrackEvaluation {
        if let lastAutoCountDate,
           now.timeIntervalSince(lastAutoCountDate) < settings.cooldownSeconds {
            let remaining = Int(settings.cooldownSeconds - now.timeIntervalSince(lastAutoCountDate))
            return BacktrackEvaluation(
                result: nil,
                statusMessage: "Cooldown · \(max(1, remaining))s"
            )
        }

        guard let travelHeading else {
            return BacktrackEvaluation(result: nil, statusMessage: "Waiting for movement")
        }

        pruneHistory(now: now)
        headingHistory.append(HeadingSample(date: now, heading: travelHeading))

        guard let recentDirection = recentDirectionHeading(at: now) else {
            return BacktrackEvaluation(
                result: nil,
                statusMessage: "Establishing recent direction…"
            )
        }

        let turnaroundDelta = bearingDifference(travelHeading, recentDirection)

        guard turnaroundDelta >= settings.turnaroundThresholdDegrees else {
            return BacktrackEvaluation(
                result: nil,
                statusMessage:
                    "Walking · recent \(Int(recentDirection))° · turn Δ\(Int(turnaroundDelta))° " +
                    "(need \(Int(settings.turnaroundThresholdDegrees))°)"
            )
        }

        lastAutoCountDate = now

        return BacktrackEvaluation(
            result: BacktrackDetectionResult(
                coordinate: CLLocationCoordinate2D(),
                note: "Turnaround · Δ\(Int(turnaroundDelta))°"
            ),
            statusMessage: "Counted · turnaround Δ\(Int(turnaroundDelta))°"
        )
    }

    private mutating func pruneHistory(now: Date) {
        let cutoff = now.addingTimeInterval(-historyRetentionSeconds)
        headingHistory.removeAll { $0.date < cutoff }
    }

    private func recentDirectionHeading(at date: Date) -> Double? {
        guard let earliest = headingHistory.first else { return nil }

        let target = date.addingTimeInterval(-directionLookbackSeconds)
        guard earliest.date <= target else { return nil }

        return headingHistory.min {
            abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target))
        }?.heading
    }

    private func bearingDifference(_ lhs: Double, _ rhs: Double) -> Double {
        let difference = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return difference > 180 ? 360 - difference : difference
    }
}
