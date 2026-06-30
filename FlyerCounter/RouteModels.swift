import CoreLocation
import Foundation

struct RouteRecord: Identifiable, Codable {
    let id: UUID
    var name: String?
    var method: String?
    var neighborhoodType: String?
    var highlighterColor: String?
    var startedAt: Date
    var endedAt: Date?
    var pausedAt: Date?
    var accumulatedRecordingSeconds: TimeInterval
    var recordingStartedAt: Date?
    var lastRecordingCheckpointAt: Date?
    var routePoints: [StoredCoordinate]
    var flyerDrops: [FlyerDrop]
    var flyerCount: Int
    var segmentMarkers: [RouteSegmentMarker]?
    /// Indices in `routePoints` where each walked segment begins after a pause/resume.
    var walkingSegmentStartIndices: [Int]?

    var resolvedSegmentMarkers: [RouteSegmentMarker] {
        segmentMarkers ?? []
    }

    var trimmedName: String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var trimmedMethod: String? {
        guard let method else { return nil }
        let trimmed = method.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var trimmedNeighborhoodType: String? {
        guard let neighborhoodType else { return nil }
        let trimmed = neighborhoodType.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var trimmedHighlighterColor: String? {
        guard let highlighterColor else { return nil }
        let trimmed = highlighterColor.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    var distanceWalked: CLLocationDistance {
        walkingSegmentsCoordinates().reduce(0) { total, segment in
            total + Self.distance(along: segment)
        }
    }

    var resolvedWalkingSegmentStartIndices: [Int] {
        let starts = walkingSegmentStartIndices ?? [0]
        return starts.isEmpty ? [0] : starts.sorted()
    }

    func walkingSegmentsCoordinates() -> [[CLLocationCoordinate2D]] {
        guard !routePoints.isEmpty else { return [] }

        let starts = resolvedWalkingSegmentStartIndices
        var segments: [[CLLocationCoordinate2D]] = []

        for (index, start) in starts.enumerated() {
            guard start < routePoints.count else { continue }

            let end = index + 1 < starts.count
                ? min(starts[index + 1], routePoints.count)
                : routePoints.count
            guard start < end else { continue }

            segments.append(routePoints[start..<end].map(\.coordinate))
        }

        if segments.isEmpty {
            return [routePoints.map(\.coordinate)]
        }

        return segments
    }

    func walkingGapConnections() -> [[CLLocationCoordinate2D]] {
        let segments = walkingSegmentsCoordinates()
        guard segments.count >= 2 else { return [] }

        var gaps: [[CLLocationCoordinate2D]] = []
        for index in 0..<(segments.count - 1) {
            guard let last = segments[index].last,
                  let first = segments[index + 1].first else {
                continue
            }
            gaps.append([last, first])
        }
        return gaps
    }

    mutating func markWalkingSegmentResume() {
        var starts = walkingSegmentStartIndices ?? [0]
        let nextStart = routePoints.count
        if starts.last != nextStart {
            starts.append(nextStart)
        }
        walkingSegmentStartIndices = starts
    }

    private static func distance(along coordinates: [CLLocationCoordinate2D]) -> CLLocationDistance {
        guard coordinates.count >= 2 else { return 0 }

        var total: CLLocationDistance = 0
        for index in 1..<coordinates.count {
            let previous = CLLocation(
                latitude: coordinates[index - 1].latitude,
                longitude: coordinates[index - 1].longitude
            )
            let current = CLLocation(
                latitude: coordinates[index].latitude,
                longitude: coordinates[index].longitude
            )
            total += current.distance(from: previous)
        }
        return total
    }

    var isInProgress: Bool {
        endedAt == nil
    }

    mutating func commitOpenRecordingSegment(at date: Date = Date()) {
        guard let recordingStartedAt else { return }
        accumulatedRecordingSeconds += max(0, date.timeIntervalSince(recordingStartedAt))
        self.recordingStartedAt = nil
        lastRecordingCheckpointAt = date
    }

    mutating func beginRecordingSegment(at date: Date = Date()) {
        recordingStartedAt = date
    }

    func recordingElapsedDuration(at date: Date = Date()) -> TimeInterval {
        let activeSegment = recordingStartedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0
        return resolvedAccumulatedRecordingSeconds + activeSegment
    }

    var frozenRecordingElapsedDuration: TimeInterval? {
        guard recordingStartedAt == nil else { return nil }
        guard pausedAt != nil || endedAt != nil else { return nil }
        return resolvedAccumulatedRecordingSeconds
    }

    private var resolvedAccumulatedRecordingSeconds: TimeInterval {
        if accumulatedRecordingSeconds > 0 {
            return accumulatedRecordingSeconds
        }
        if let end = endedAt ?? pausedAt {
            return max(0, end.timeIntervalSince(startedAt))
        }
        return 0
    }

    var displayTitle: String {
        trimmedName ?? RouteDateFormatting.routeTimeOnlyRange(
            startedAt: startedAt,
            endedAt: endedAt
        )
    }

    mutating func ensureStartMarker(at coordinate: CLLocationCoordinate2D) {
        var markers = segmentMarkers ?? []
        guard markers.isEmpty else { return }
        markers.append(RouteSegmentMarker(label: "A", coordinate: coordinate))
        segmentMarkers = markers
    }

    mutating func appendEndSegmentMarker(at coordinate: CLLocationCoordinate2D) {
        var markers = segmentMarkers ?? []

        if markers.isEmpty {
            let startCoordinate = routePoints.first?.coordinate ?? coordinate
            markers.append(RouteSegmentMarker(label: "A", coordinate: startCoordinate))
        }

        let label = RouteSegmentMarker.letter(for: markers.count)
        markers.append(RouteSegmentMarker(label: label, coordinate: coordinate))
        segmentMarkers = markers
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case method
        case neighborhoodType
        case highlighterColor
        case startedAt
        case endedAt
        case pausedAt
        case accumulatedRecordingSeconds
        case recordingStartedAt
        case lastRecordingCheckpointAt
        case routePoints
        case flyerDrops
        case flyerCount
        case segmentMarkers
        case walkingSegmentStartIndices
    }

    init(
        id: UUID,
        name: String?,
        method: String?,
        neighborhoodType: String?,
        highlighterColor: String?,
        startedAt: Date,
        endedAt: Date?,
        pausedAt: Date?,
        accumulatedRecordingSeconds: TimeInterval = 0,
        recordingStartedAt: Date? = nil,
        lastRecordingCheckpointAt: Date? = nil,
        routePoints: [StoredCoordinate],
        flyerDrops: [FlyerDrop],
        flyerCount: Int,
        segmentMarkers: [RouteSegmentMarker]?,
        walkingSegmentStartIndices: [Int]? = nil
    ) {
        self.id = id
        self.name = name
        self.method = method
        self.neighborhoodType = neighborhoodType
        self.highlighterColor = highlighterColor
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.pausedAt = pausedAt
        self.accumulatedRecordingSeconds = accumulatedRecordingSeconds
        self.recordingStartedAt = recordingStartedAt
        self.lastRecordingCheckpointAt = lastRecordingCheckpointAt
        self.routePoints = routePoints
        self.flyerDrops = flyerDrops
        self.flyerCount = flyerCount
        self.segmentMarkers = segmentMarkers
        self.walkingSegmentStartIndices = walkingSegmentStartIndices
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        method = try container.decodeIfPresent(String.self, forKey: .method)
        neighborhoodType = try container.decodeIfPresent(String.self, forKey: .neighborhoodType)
        highlighterColor = try container.decodeIfPresent(String.self, forKey: .highlighterColor)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        endedAt = try container.decodeIfPresent(Date.self, forKey: .endedAt)
        pausedAt = try container.decodeIfPresent(Date.self, forKey: .pausedAt)
        accumulatedRecordingSeconds = try container.decodeIfPresent(
            TimeInterval.self,
            forKey: .accumulatedRecordingSeconds
        ) ?? 0
        recordingStartedAt = try container.decodeIfPresent(Date.self, forKey: .recordingStartedAt)
        lastRecordingCheckpointAt = try container.decodeIfPresent(
            Date.self,
            forKey: .lastRecordingCheckpointAt
        )
        routePoints = try container.decode([StoredCoordinate].self, forKey: .routePoints)
        flyerDrops = try container.decode([FlyerDrop].self, forKey: .flyerDrops)
        flyerCount = try container.decode(Int.self, forKey: .flyerCount)
        segmentMarkers = try container.decodeIfPresent([RouteSegmentMarker].self, forKey: .segmentMarkers)
        walkingSegmentStartIndices = try container.decodeIfPresent(
            [Int].self,
            forKey: .walkingSegmentStartIndices
        )
    }
}

struct RouteSegmentMarker: Identifiable, Codable, Equatable {
    let id: UUID
    let label: String
    let latitude: Double
    let longitude: Double

    init(id: UUID = UUID(), label: String, coordinate: CLLocationCoordinate2D) {
        self.id = id
        self.label = label
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func letter(for index: Int) -> String {
        guard (0..<26).contains(index) else { return "?" }
        return String(UnicodeScalar(65 + index)!)
    }
}

struct StoredCoordinate: Codable, Equatable {
    let latitude: Double
    let longitude: Double

    init(coordinate: CLLocationCoordinate2D) {
        latitude = coordinate.latitude
        longitude = coordinate.longitude
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct RouteArchive: Codable {
    var routes: [RouteRecord]
    var activeRouteId: UUID?
}

struct LegacySavedRoute: Codable {
    var routePoints: [StoredCoordinate]
    var flyerDrops: [FlyerDrop]
    var flyerCount: Int
    var isTracking: Bool
}

enum RouteStorage {
    private static let archiveKey = "routeArchive"
    private static let legacyKey = "savedRoute"
    private static let wasBackgroundedWhileRecordingKey = "wasBackgroundedWhileRecording"

    static func setWasBackgroundedWhileRecording(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: wasBackgroundedWhileRecordingKey)
    }

    static func consumeWasBackgroundedWhileRecording() -> Bool {
        let value = UserDefaults.standard.bool(forKey: wasBackgroundedWhileRecordingKey)
        UserDefaults.standard.set(false, forKey: wasBackgroundedWhileRecordingKey)
        return value
    }

    static func loadArchive() -> RouteArchive? {
        guard let data = UserDefaults.standard.data(forKey: archiveKey) else { return nil }
        return try? JSONDecoder().decode(RouteArchive.self, from: data)
    }

    static func saveArchive(_ archive: RouteArchive) {
        guard let data = try? JSONEncoder().encode(archive) else { return }
        UserDefaults.standard.set(data, forKey: archiveKey)
    }

    static func loadLegacyRoute() -> LegacySavedRoute? {
        guard let data = UserDefaults.standard.data(forKey: legacyKey) else { return nil }
        return try? JSONDecoder().decode(LegacySavedRoute.self, from: data)
    }

    static func removeLegacyRoute() {
        UserDefaults.standard.removeObject(forKey: legacyKey)
    }
}

struct RouteDayGroup: Identifiable {
    let id: Date
    let header: String
    let routes: [RouteRecord]
}

enum RouteDateFormatting {
    private static let calendar = Calendar.current

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "h:mma"
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMMM d, yyyy h:mma"
        return formatter
    }()

    static func routeTimeRange(startedAt: Date, endedAt: Date?) -> String {
        guard let endedAt else {
            return "Started \(formatDateTime(startedAt))"
        }

        if calendar.isDate(startedAt, inSameDayAs: endedAt) {
            return "\(formatDateTime(startedAt)) - \(formatTime(endedAt))"
        }

        return "\(formatDateTime(startedAt)) - \(formatDateTime(endedAt))"
    }

    static func routeTimeOnlyRange(startedAt: Date, endedAt: Date?) -> String {
        guard let endedAt else {
            return "\(formatTime(startedAt)) - In progress"
        }

        return "\(formatTime(startedAt)) - \(formatTime(endedAt))"
    }

    static func formatDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    static func dayHeader(for date: Date) -> String {
        let weekday = date.formatted(.dateTime.weekday(.wide))
        let month = date.formatted(.dateTime.month(.wide))
        let day = calendar.component(.day, from: date)
        let year = calendar.component(.year, from: date)
        return "\(weekday), \(month) \(ordinal(day)), \(year)"
    }

    static func groupedByDay(_ routes: [RouteRecord]) -> [RouteDayGroup] {
        let grouped = Dictionary(grouping: routes) { route in
            calendar.startOfDay(for: route.startedAt)
        }

        return grouped
            .map { day, dayRoutes in
                RouteDayGroup(
                    id: day,
                    header: dayHeader(for: day),
                    routes: dayRoutes.sorted { $0.startedAt < $1.startedAt }
                )
            }
            .sorted { $0.id > $1.id }
    }

    private static func formatTime(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    private static func formatDateTime(_ date: Date) -> String {
        dateTimeFormatter.string(from: date)
    }

    private static func ordinal(_ day: Int) -> String {
        let suffix: String
        switch day % 100 {
        case 11...13:
            suffix = "th"
        default:
            switch day % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(day)\(suffix)"
    }
}
