import CoreLocation
import Foundation

struct AutoFlyerDetectionResult {
    let coordinate: CLLocationCoordinate2D
    let note: String
}

struct AutoFlyerEvaluation {
    let result: AutoFlyerDetectionResult?
    let statusMessage: String
}

struct CompassTurnaroundFlyerDetector {
    /// How far back in time `recent` is measured from the present moment.
    static let comparisonLookbackSeconds: TimeInterval = 2
    /// Re-evaluate on this interval so the rolling window advances even when the compass is still.
    static let historyRefreshIntervalSeconds: TimeInterval = 1

    private struct HeadingSample {
        let date: Date
        let heading: Double
    }

    private var headingHistory: [HeadingSample] = []
    private var lastAutoCountDate: Date?

    private let historyRetentionSeconds: TimeInterval = 15

    mutating func reset() {
        headingHistory = []
        lastAutoCountDate = nil
    }

    /// Compares live heading to the heading from exactly `comparisonLookbackSeconds` ago.
    mutating func evaluateLive(
        deviceHeading: Double?,
        settings: CompassTurnaroundSettings,
        now: Date = Date()
    ) -> AutoFlyerEvaluation {
        guard let facing = deviceHeading else {
            return AutoFlyerEvaluation(result: nil, statusMessage: "Waiting for compass")
        }

        recordSample(heading: facing, at: now)

        guard let recent = headingAtLookback(from: now) else {
            return AutoFlyerEvaluation(
                result: nil,
                statusMessage: "Facing \(Int(facing))° · establishing 2 s lookback…"
            )
        }

        let turnaroundDelta = bearingDifference(facing, recent)
        var statusMessage =
            "Facing \(Int(facing))° · recent \(Int(recent))° · " +
            "turn Δ\(Int(turnaroundDelta))° (need \(Int(settings.turnaroundThresholdDegrees))°)"

        if let lastAutoCountDate,
           now.timeIntervalSince(lastAutoCountDate) < settings.cooldownSeconds {
            let remaining = Int(settings.cooldownSeconds - now.timeIntervalSince(lastAutoCountDate))
            statusMessage += " · cooldown \(max(1, remaining))s"
            return AutoFlyerEvaluation(result: nil, statusMessage: statusMessage)
        }

        guard turnaroundDelta >= settings.turnaroundThresholdDegrees else {
            return AutoFlyerEvaluation(result: nil, statusMessage: statusMessage)
        }

        lastAutoCountDate = now

        return AutoFlyerEvaluation(
            result: AutoFlyerDetectionResult(
                coordinate: CLLocationCoordinate2D(),
                note: "Turnaround · Δ\(Int(turnaroundDelta))°"
            ),
            statusMessage: "Counted · turnaround Δ\(Int(turnaroundDelta))°"
        )
    }

    private mutating func recordSample(heading: Double, at date: Date) {
        pruneHistory(now: date)
        headingHistory.append(HeadingSample(date: date, heading: heading))
    }

    private mutating func pruneHistory(now: Date) {
        let cutoff = now.addingTimeInterval(-historyRetentionSeconds)
        headingHistory.removeAll { $0.date < cutoff }
    }

    private func headingAtLookback(from now: Date) -> Double? {
        let target = now.addingTimeInterval(-Self.comparisonLookbackSeconds)
        let eligibleSamples = headingHistory.filter { $0.date <= target }
        guard let closest = eligibleSamples.min(by: {
            target.timeIntervalSince($0.date) < target.timeIntervalSince($1.date)
        }) else {
            return nil
        }

        return closest.heading
    }

    private func bearingDifference(_ lhs: Double, _ rhs: Double) -> Double {
        let difference = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return difference > 180 ? 360 - difference : difference
    }
}
