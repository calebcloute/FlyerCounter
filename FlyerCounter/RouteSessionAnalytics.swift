import CoreLocation
import Foundation

struct RouteStopEvent: Codable, Identifiable, Equatable {
    let id: UUID
    let startedAt: Date
    let endedAt: Date
    let durationSeconds: TimeInterval

    init(id: UUID = UUID(), startedAt: Date, endedAt: Date) {
        self.id = id
        self.startedAt = startedAt
        self.endedAt = endedAt
        durationSeconds = max(0, endedAt.timeIntervalSince(startedAt))
    }
}

struct RouteLiveStats: Equatable {
    var isSessionActive = false
    var isCurrentlyStopped = false
    var currentStopDurationSeconds: TimeInterval = 0
    var stopCount = 0
    var totalStoppedSeconds: TimeInterval = 0
    var totalMovingSeconds: TimeInterval = 0
    var currentSpeedMPS: Double = 0
    var averageMovingSpeedMPS: Double = 0
    var maxSpeedMPS: Double = 0
    var averageAbsoluteAccelerationMPS2: Double = 0
    var averageSpeedChangeMPS: Double = 0
    var significantTurnCount = 0
    var sampleCount = 0
    var averageHorizontalAccuracyMeters: Double = 0
    var sessionDurationSeconds: TimeInterval = 0
    var recentStops: [RouteStopEvent] = []

    static let idle = RouteLiveStats()

    var movingFraction: Double {
        guard sessionDurationSeconds > 0 else { return 0 }
        return totalMovingSeconds / sessionDurationSeconds
    }

    var averageStopDurationSeconds: TimeInterval {
        guard stopCount > 0 else { return 0 }
        return totalStoppedSeconds / Double(stopCount)
    }
}

struct RouteSessionSnapshot: Codable, Identifiable, Equatable {
    let routeId: UUID
    let routeName: String?
    let recordedAt: Date
    let stopCount: Int
    let totalStoppedSeconds: TimeInterval
    let totalMovingSeconds: TimeInterval
    let sessionDurationSeconds: TimeInterval
    let averageMovingSpeedMPS: Double
    let maxSpeedMPS: Double
    let averageAbsoluteAccelerationMPS2: Double
    let averageSpeedChangeMPS: Double
    let significantTurnCount: Int
    let sampleCount: Int
    let averageHorizontalAccuracyMeters: Double
    let stops: [RouteStopEvent]

    var id: UUID { routeId }

    var movingFraction: Double {
        guard sessionDurationSeconds > 0 else { return 0 }
        return totalMovingSeconds / sessionDurationSeconds
    }

    var averageStopDurationSeconds: TimeInterval {
        guard stopCount > 0 else { return 0 }
        return totalStoppedSeconds / Double(stopCount)
    }

    init(
        routeId: UUID,
        routeName: String?,
        recordedAt: Date,
        live: RouteLiveStats,
        stops: [RouteStopEvent]
    ) {
        self.routeId = routeId
        self.routeName = routeName
        self.recordedAt = recordedAt
        stopCount = stops.count
        totalStoppedSeconds = stops.reduce(0) { $0 + $1.durationSeconds }
        totalMovingSeconds = live.totalMovingSeconds
        sessionDurationSeconds = live.sessionDurationSeconds
        averageMovingSpeedMPS = live.averageMovingSpeedMPS
        maxSpeedMPS = live.maxSpeedMPS
        averageAbsoluteAccelerationMPS2 = live.averageAbsoluteAccelerationMPS2
        averageSpeedChangeMPS = live.averageSpeedChangeMPS
        significantTurnCount = live.significantTurnCount
        sampleCount = live.sampleCount
        averageHorizontalAccuracyMeters = live.averageHorizontalAccuracyMeters
        self.stops = stops
    }
}

enum RouteAnalyticsStorage {
    private static let storageKey = "routeSessionAnalytics"

    static func loadAll() -> [RouteSessionSnapshot] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let snapshots = try? JSONDecoder().decode([RouteSessionSnapshot].self, from: data) else {
            return []
        }
        return snapshots.sorted { $0.recordedAt > $1.recordedAt }
    }

    static func save(_ snapshots: [RouteSessionSnapshot]) {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static func upsert(_ snapshot: RouteSessionSnapshot) {
        var snapshots = loadAll()
        snapshots.removeAll { $0.routeId == snapshot.routeId }
        snapshots.insert(snapshot, at: 0)
        save(snapshots)
    }

    static func remove(routeId: UUID) {
        var snapshots = loadAll()
        snapshots.removeAll { $0.routeId == routeId }
        save(snapshots)
    }
}

enum RouteAnalyticsFormatting {
    static func speedMPH(_ metersPerSecond: Double) -> String {
        String(format: "%.1f mph", metersPerSecond * 2.23694)
    }

    static func speedMPS(_ metersPerSecond: Double) -> String {
        String(format: "%.2f m/s", metersPerSecond)
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    static func percent(_ fraction: Double) -> String {
        String(format: "%.0f%%", max(0, min(1, fraction)) * 100)
    }

    static func acceleration(_ metersPerSecondSquared: Double) -> String {
        String(format: "%.2f m/s²", metersPerSecondSquared)
    }
}

struct RouteSessionTracker {
    private var sessionStartedAt: Date?
    private var lastSampleDate: Date?
    private var lastSampleLocation: CLLocation?
    private var lastSampleSpeed: Double?
    private var lastSampleHeading: Double?

    private var isInStop = false
    private var currentStopStartedAt: Date?
    private var completedStops: [RouteStopEvent] = []

    private var stopCount = 0
    private var totalStoppedSeconds: TimeInterval = 0
    private var totalMovingSeconds: TimeInterval = 0

    private var movingSpeedTotal: Double = 0
    private var movingSpeedSamples = 0
    private var maxSpeed: Double = 0

    private var accelerationTotal: Double = 0
    private var accelerationSamples = 0
    private var speedChangeTotal: Double = 0

    private var significantTurnCount = 0
    private var sampleCount = 0
    private var accuracyTotal: Double = 0
    private var currentSpeed: Double = 0

    private let stopSpeedThreshold: Double = 0.4
    private let resumeSpeedThreshold: Double = 0.6
    private let minimumStopDuration: TimeInterval = 2
    private let significantTurnDegrees: Double = 45
    private let movingSpeedThreshold: Double = 0.5

    mutating func reset(startedAt: Date = Date()) {
        sessionStartedAt = startedAt
        lastSampleDate = nil
        lastSampleLocation = nil
        lastSampleSpeed = nil
        lastSampleHeading = nil
        isInStop = false
        currentStopStartedAt = nil
        completedStops = []
        stopCount = 0
        totalStoppedSeconds = 0
        totalMovingSeconds = 0
        movingSpeedTotal = 0
        movingSpeedSamples = 0
        maxSpeed = 0
        accelerationTotal = 0
        accelerationSamples = 0
        speedChangeTotal = 0
        significantTurnCount = 0
        sampleCount = 0
        accuracyTotal = 0
        currentSpeed = 0
    }

    mutating func process(
        location: CLLocation,
        travelHeading: Double?,
        now: Date = Date()
    ) -> RouteLiveStats {
        guard let sessionStartedAt else { return .idle }

        let sampleDate = location.timestamp > (lastSampleDate ?? .distantPast) ? location.timestamp : now
        let speed = resolvedSpeed(for: location, sampleDate: sampleDate)
        let deltaTime = lastSampleDate.map { max(0.05, sampleDate.timeIntervalSince($0)) } ?? 0

        if let lastSampleSpeed, deltaTime > 0 {
            let speedChange = speed - lastSampleSpeed
            accelerationTotal += abs(speedChange / deltaTime)
            accelerationSamples += 1
            speedChangeTotal += abs(speedChange)
        }

        if let travelHeading, let lastSampleHeading {
            let turnDelta = bearingDifference(travelHeading, lastSampleHeading)
            if turnDelta >= significantTurnDegrees {
                significantTurnCount += 1
            }
        }

        if deltaTime > 0 {
            if speed >= resumeSpeedThreshold {
                if isInStop, let stopStart = currentStopStartedAt {
                    let duration = sampleDate.timeIntervalSince(stopStart)
                    if duration >= minimumStopDuration {
                        completedStops.append(RouteStopEvent(startedAt: stopStart, endedAt: sampleDate))
                        stopCount += 1
                        totalStoppedSeconds += duration
                    }
                }
                isInStop = false
                currentStopStartedAt = nil
                totalMovingSeconds += deltaTime
                if speed >= movingSpeedThreshold {
                    movingSpeedTotal += speed
                    movingSpeedSamples += 1
                }
            } else if speed <= stopSpeedThreshold {
                if !isInStop {
                    isInStop = true
                    currentStopStartedAt = sampleDate
                }
                totalStoppedSeconds += deltaTime
            }
        }

        maxSpeed = max(maxSpeed, speed)
        sampleCount += 1
        currentSpeed = speed
        if location.horizontalAccuracy >= 0 {
            accuracyTotal += location.horizontalAccuracy
        }

        lastSampleDate = sampleDate
        lastSampleLocation = location
        lastSampleSpeed = speed
        if let travelHeading {
            lastSampleHeading = travelHeading
        }

        return buildLiveStats(sessionStartedAt: sessionStartedAt, now: sampleDate)
    }

    mutating func finalize(
        routeId: UUID,
        routeName: String?,
        now: Date = Date()
    ) -> RouteSessionSnapshot? {
        guard let sessionStartedAt else { return nil }

        if isInStop, let stopStart = currentStopStartedAt {
            let duration = now.timeIntervalSince(stopStart)
            if duration >= minimumStopDuration {
                completedStops.append(RouteStopEvent(startedAt: stopStart, endedAt: now))
                stopCount += 1
                totalStoppedSeconds += duration
            }
            isInStop = false
            currentStopStartedAt = nil
        }

        let live = buildLiveStats(sessionStartedAt: sessionStartedAt, now: now)
        let snapshot = RouteSessionSnapshot(
            routeId: routeId,
            routeName: routeName,
            recordedAt: now,
            live: live,
            stops: completedStops
        )

        self.sessionStartedAt = nil
        return snapshot
    }

    private func buildLiveStats(sessionStartedAt: Date, now: Date) -> RouteLiveStats {
        let currentStopDuration: TimeInterval
        if isInStop, let currentStopStartedAt {
            currentStopDuration = now.timeIntervalSince(currentStopStartedAt)
        } else {
            currentStopDuration = 0
        }

        var displayStoppedSeconds = totalStoppedSeconds
        if isInStop {
            displayStoppedSeconds += currentStopDuration
        }

        return RouteLiveStats(
            isSessionActive: true,
            isCurrentlyStopped: isInStop,
            currentStopDurationSeconds: currentStopDuration,
            stopCount: stopCount + (isInStop && currentStopDuration >= minimumStopDuration ? 1 : 0),
            totalStoppedSeconds: displayStoppedSeconds,
            totalMovingSeconds: totalMovingSeconds,
            currentSpeedMPS: currentSpeed,
            averageMovingSpeedMPS: movingSpeedSamples > 0
                ? movingSpeedTotal / Double(movingSpeedSamples) : 0,
            maxSpeedMPS: maxSpeed,
            averageAbsoluteAccelerationMPS2: accelerationSamples > 0
                ? accelerationTotal / Double(accelerationSamples) : 0,
            averageSpeedChangeMPS: accelerationSamples > 0
                ? speedChangeTotal / Double(accelerationSamples) : 0,
            significantTurnCount: significantTurnCount,
            sampleCount: sampleCount,
            averageHorizontalAccuracyMeters: sampleCount > 0
                ? accuracyTotal / Double(sampleCount) : 0,
            sessionDurationSeconds: now.timeIntervalSince(sessionStartedAt),
            recentStops: Array(completedStops.suffix(5))
        )
    }

    private func resolvedSpeed(for location: CLLocation, sampleDate: Date) -> Double {
        if location.speed >= 0 {
            return location.speed
        }

        guard let lastSampleLocation, let lastSampleDate else { return 0 }
        let deltaTime = sampleDate.timeIntervalSince(lastSampleDate)
        guard deltaTime > 0 else { return 0 }
        return location.distance(from: lastSampleLocation) / deltaTime
    }

    private func bearingDifference(_ lhs: Double, _ rhs: Double) -> Double {
        let difference = abs(lhs - rhs).truncatingRemainder(dividingBy: 360)
        return difference > 180 ? 360 - difference : difference
    }
}
