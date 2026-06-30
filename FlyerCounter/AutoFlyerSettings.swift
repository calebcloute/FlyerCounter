import Combine
import Foundation
import SwiftUI

enum AutoFlyerCountingMethod: String, Codable, CaseIterable, Identifiable {
    case compassTurnaround
    case pathBacktrack
    case plannedRouteDivergence

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compassTurnaround:
            "Turnaround (uses compass only)"
        case .pathBacktrack:
            "Backtrack (uses GPS only)"
        case .plannedRouteDivergence:
            "Planned route divergence"
        }
    }
}

struct CompassTurnaroundSettings: Codable, Equatable {
    var turnaroundThresholdDegrees: Double = 150
    var cooldownSeconds: Double = 8
}

struct PlannedRouteDetectionSettings: Codable, Equatable {
    var nearPlanMeters: Double = 3
    var divergenceThresholdMeters: Double = 5
    var cooldownSeconds: Double = 8
    var maximumGPSAccuracyMeters: Double = 25
}

struct PathBacktrackSettings: Codable, Equatable {
    var overlapRadiusMeters: Double = 4
    var minBacktrackSeparationMeters: Double = 10
    var cooldownSeconds: Double = 8
    var maximumGPSAccuracyMeters: Double = 25
}

struct VoiceAnnouncementSettings: Codable, Equatable {
    var speakFlyerCountedTurnaround: Bool = true
    var speakFlyerCountedBacktrack: Bool = true
    var speakFlyerCountedPlannedRoute: Bool = true
    var speakCooldownCountdown: Bool = true
    var speakEstablishingWait: Bool = true
}

struct AutoFlyerSettings: Codable, Equatable {
    var isVoiceFeedbackEnabled: Bool = false
    var voiceAnnouncements = VoiceAnnouncementSettings()
    var method: AutoFlyerCountingMethod = .compassTurnaround
    var turnaround = CompassTurnaroundSettings()
    var pathBacktrack = PathBacktrackSettings()
    var plannedRoute = PlannedRouteDetectionSettings()
}

enum AutoFlyerSettingsStorage {
    private static let storageKey = "autoFlyerSettings"

    static func load() -> AutoFlyerSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else {
            return AutoFlyerSettings()
        }

        if let settings = try? JSONDecoder().decode(AutoFlyerSettings.self, from: data) {
            return settings
        }

        return migrateLegacySettings(from: data)
    }

    static func save(_ settings: AutoFlyerSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private static func migrateLegacySettings(from data: Data) -> AutoFlyerSettings {
        struct LegacyAutoFlyerSettings: Codable {
            var compassTurnaround: CompassTurnaroundSettings = CompassTurnaroundSettings()
        }

        guard let legacy = try? JSONDecoder().decode(LegacyAutoFlyerSettings.self, from: data) else {
            return AutoFlyerSettings()
        }

        return AutoFlyerSettings(turnaround: legacy.compassTurnaround)
    }
}

@MainActor
final class AutoFlyerSettingsStore: ObservableObject {
    @Published var settings: AutoFlyerSettings {
        didSet {
            if let settingsLockStore {
                let enforced = settingsLockStore.enforcedAutoFlyerSettings(settings)
                if enforced != settings {
                    settings = enforced
                    return
                }
            }
            AutoFlyerSettingsStorage.save(settings)
        }
    }

    private var settingsLockStore: SettingsLockStore?

    init() {
        settings = AutoFlyerSettingsStorage.load()
    }

    func bind(settingsLockStore: SettingsLockStore) {
        self.settingsLockStore = settingsLockStore
        applySettingsLock(from: settingsLockStore)
    }

    func applySettingsLock(from settingsLockStore: SettingsLockStore) {
        let enforced = settingsLockStore.enforcedAutoFlyerSettings(settings)
        if enforced != settings {
            settings = enforced
        } else {
            AutoFlyerSettingsStorage.save(settings)
        }
    }
}

struct CompassTurnaroundSettingsSection: View {
    @Binding var settings: CompassTurnaroundSettings
    var isLocked = false

    var body: some View {
        Section {
            lockedSliderRow(
                title: "Turn threshold: \(Int(settings.turnaroundThresholdDegrees))°",
                value: $settings.turnaroundThresholdDegrees,
                range: 120...180,
                step: 5
            )

            lockedSliderRow(
                title: "Cooldown: \(Int(settings.cooldownSeconds)) s",
                value: $settings.cooldownSeconds,
                range: 3...30,
                step: 1
            )
        } header: {
            Text("Turnaround")
        } footer: {
            Text(
                "Counts a flyer when live compass heading exceeds the turn threshold compared to " +
                "where you were facing exactly 2 seconds ago. Each new or resumed route starts with a cooldown " +
                "(same length as above) before auto counting begins. Hold the phone upright in portrait for best results."
            )
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func lockedSliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        if isLocked {
            Text(title + " (locked)")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                Slider(value: value, in: range, step: step)
            }
        }
    }
}

struct AutomaticFlyerCountingSection: View {
    @ObservedObject var store: AutoFlyerSettingsStore
    @ObservedObject var settingsLockStore: SettingsLockStore

    private var isLocked: Bool { settingsLockStore.isLocked }

    var body: some View {
        Section {
            Picker("Counting method", selection: $store.settings.method) {
                ForEach(AutoFlyerCountingMethod.allCases) { method in
                    Text(method.title).tag(method)
                }
            }
            .disabled(isLocked)
        } header: {
            Text("Flyer Counting")
        } footer: {
            if isLocked {
                Text(
                    "Counting method and thresholds are locked. " +
                    "Unlock in Lock Counting Method Settings to change them."
                )
                .foregroundStyle(.orange)
            } else {
                Text(
                    "Flyers are counted automatically while a route is recording using the method you choose. " +
                    "Use -1 Flyer to undo a mistaken count. Each count gives one vibration in the app, or a notification " +
                    "on the lock screen. Voice announcements work on the lock screen when Speak testing announcements is on."
                )
                .foregroundStyle(.secondary)
            }
        }

        Toggle("Speak testing announcements", isOn: $store.settings.isVoiceFeedbackEnabled)

        if store.settings.isVoiceFeedbackEnabled {
            VoiceAnnouncementSettingsSection(settings: $store.settings.voiceAnnouncements)
        }

        switch store.settings.method {
        case .compassTurnaround:
            CompassTurnaroundSettingsSection(
                settings: $store.settings.turnaround,
                isLocked: isLocked
            )
        case .pathBacktrack:
            PathBacktrackSettingsSection(
                settings: $store.settings.pathBacktrack,
                isLocked: isLocked
            )
        case .plannedRouteDivergence:
            PlannedRouteDetectionSettingsSection(
                settings: $store.settings.plannedRoute,
                isLocked: isLocked
            )
        }
    }
}

struct VoiceAnnouncementSettingsSection: View {
    @Binding var settings: VoiceAnnouncementSettings

    var body: some View {
        Section {
            Toggle("Flyer counted (turnaround)", isOn: $settings.speakFlyerCountedTurnaround)
            Toggle("Flyer counted (backtrack)", isOn: $settings.speakFlyerCountedBacktrack)
            Toggle("Flyer counted (planned route)", isOn: $settings.speakFlyerCountedPlannedRoute)
            Toggle("Cooldown countdown", isOn: $settings.speakCooldownCountdown)
            Toggle("Establishing wait", isOn: $settings.speakEstablishingWait)
        } header: {
            Text("Announcements")
        } footer: {
            Text(
                "Choose which spoken cues play while testing auto counting. " +
                "Establishing wait is the repeated “wait” during the turnaround 2-second lookback."
            )
            .foregroundStyle(.secondary)
        }
    }
}

struct PathBacktrackSettingsSection: View {
    @Binding var settings: PathBacktrackSettings
    var isLocked = false

    var body: some View {
        Section {
            lockedSliderRow(
                title: "Distance from path line: \(Int(settings.overlapRadiusMeters)) m",
                value: $settings.overlapRadiusMeters,
                range: 2...8,
                step: 1
            )

            lockedSliderRow(
                title: "Min path behind furthest point: \(Int(settings.minBacktrackSeparationMeters)) m",
                value: $settings.minBacktrackSeparationMeters,
                range: 6...25,
                step: 1
            )

            lockedSliderRow(
                title: "Cooldown: \(Int(settings.cooldownSeconds)) s",
                value: $settings.cooldownSeconds,
                range: 3...30,
                step: 1
            )

            lockedSliderRow(
                title: "Max GPS accuracy: \(Int(settings.maximumGPSAccuracyMeters)) m",
                value: $settings.maximumGPSAccuracyMeters,
                range: 10...40,
                step: 5
            )
        } header: {
            Text("Path Backtrack")
        } footer: {
            Text(
                "Counts a flyer at the furthest point you reached when your current position is within " +
                "the overlap radius of any part of your recorded path line — not just the GPS dots. " +
                "The overlap must be at least \(Int(settings.minBacktrackSeparationMeters)) m back along " +
                "the path from your furthest point."
            )
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func lockedSliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        if isLocked {
            Text(title + " (locked)")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                Slider(value: value, in: range, step: step)
            }
        }
    }
}

struct PlannedRouteDetectionSettingsSection: View {
    @Binding var settings: PlannedRouteDetectionSettings
    var isLocked = false

    var body: some View {
        Section {
            lockedSliderRow(
                title: "Near plan: \(Int(settings.nearPlanMeters)) m",
                value: $settings.nearPlanMeters,
                range: 2...8,
                step: 1
            )

            lockedSliderRow(
                title: "Divergence threshold: \(Int(settings.divergenceThresholdMeters)) m",
                value: $settings.divergenceThresholdMeters,
                range: 4...15,
                step: 1
            )

            lockedSliderRow(
                title: "Cooldown: \(Int(settings.cooldownSeconds)) s",
                value: $settings.cooldownSeconds,
                range: 3...30,
                step: 1
            )

            lockedSliderRow(
                title: "Max GPS accuracy: \(Int(settings.maximumGPSAccuracyMeters)) m",
                value: $settings.maximumGPSAccuracyMeters,
                range: 10...40,
                step: 5
            )
        } header: {
            Text("Planned Route")
        } footer: {
            Text(
                "Counts a flyer after you were on the active walking plan and then move farther than " +
                "the divergence threshold away from it. Corners are already in the saved plan polyline. " +
                "Choose an active plan in the Route Planner tab."
            )
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func lockedSliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        if isLocked {
            Text(title + " (locked)")
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                Slider(value: value, in: range, step: step)
            }
        }
    }
}
