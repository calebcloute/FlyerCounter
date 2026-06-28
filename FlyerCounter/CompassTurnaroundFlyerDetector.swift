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
    static let sampleIntervalSeconds: TimeInterval = 2

    /// Heading captured at the most recent 2-second tick boundary. Updates only on ticks.
    private(set) var lastTickHeading: Double?
    private var lastAutoCountDate: Date?

    mutating func reset() {
        lastTickHeading = nil
        lastAutoCountDate = nil
    }

    /// Seeds the T=0 tick when recording starts.
    mutating func seedInitialTick(_ heading: Double) {
        lastTickHeading = heading
    }

    /// Advances `recent` to a new fixed tick snapshot.
    mutating func advanceTick(to heading: Double) {
        lastTickHeading = heading
    }

    /// Compares live compass heading against the last tick (`recent`). Called on every heading update.
    mutating func evaluateLive(
        deviceHeading: Double?,
        settings: CompassTurnaroundSettings,
        now: Date = Date()
    ) -> AutoFlyerEvaluation {
        guard let facing = deviceHeading else {
            return AutoFlyerEvaluation(result: nil, statusMessage: "Waiting for compass")
        }

        guard let recent = lastTickHeading else {
            return AutoFlyerEvaluation(
                result: nil,
                statusMessage: "Facing \(Int(facing))° · waiting for first tick…"
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

    private func bearingDifference(_ lhs: Double, _ rhs: Double) -> Double {
        let difference = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return difference > 180 ? 360 - difference : difference
    }
}
