import Combine
import Foundation
import SwiftUI

enum AutoFlyerCountingMethod: String, Codable, CaseIterable, Identifiable {
    case compassTurnaround
    case plannedRouteDivergence

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compassTurnaround:
            "Turnaround (compass)"
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

struct AutoFlyerSettings: Codable, Equatable {
    var isEnabled: Bool = false
    var isVoiceFeedbackEnabled: Bool = false
    var method: AutoFlyerCountingMethod = .compassTurnaround
    var turnaround = CompassTurnaroundSettings()
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
            var isEnabled: Bool = false
            var compassTurnaround: CompassTurnaroundSettings = CompassTurnaroundSettings()
        }

        guard let legacy = try? JSONDecoder().decode(LegacyAutoFlyerSettings.self, from: data) else {
            return AutoFlyerSettings()
        }

        return AutoFlyerSettings(
            isEnabled: legacy.isEnabled,
            turnaround: legacy.compassTurnaround
        )
    }
}

@MainActor
final class AutoFlyerSettingsStore: ObservableObject {
    @Published var settings: AutoFlyerSettings {
        didSet {
            AutoFlyerSettingsStorage.save(settings)
        }
    }

    init() {
        settings = AutoFlyerSettingsStorage.load()
    }
}

struct CompassTurnaroundSettingsSection: View {
    @Binding var settings: CompassTurnaroundSettings

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Turn threshold: \(Int(settings.turnaroundThresholdDegrees))°")
                Slider(value: $settings.turnaroundThresholdDegrees, in: 120...180, step: 5)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Cooldown: \(Int(settings.cooldownSeconds)) s")
                Slider(value: $settings.cooldownSeconds, in: 3...30, step: 1)
            }
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
}

struct AutomaticFlyerCountingSection: View {
    @ObservedObject var store: AutoFlyerSettingsStore

    var body: some View {
        Section {
            Toggle("Enable automatic counting", isOn: $store.settings.isEnabled)
        } header: {
            Text("Automatic Flyer Counting")
        } footer: {
            Text(
                "Uses turnaround compass detection or planned-route divergence while a route is recording. " +
                "Manual +1 and -1 still work. Each auto count gives one vibration in the app, " +
                "or a notification on the lock screen. Voice announcements work on the lock screen " +
                "when Speak testing announcements is on."
            )
            .foregroundStyle(.secondary)
        }

        if store.settings.isEnabled {
            Toggle("Speak testing announcements", isOn: $store.settings.isVoiceFeedbackEnabled)

            Picker("Counting method", selection: $store.settings.method) {
                ForEach(AutoFlyerCountingMethod.allCases) { method in
                    Text(method.title).tag(method)
                }
            }

            switch store.settings.method {
            case .compassTurnaround:
                CompassTurnaroundSettingsSection(settings: $store.settings.turnaround)
            case .plannedRouteDivergence:
                PlannedRouteDetectionSettingsSection(settings: $store.settings.plannedRoute)
            }
        }
    }
}

struct PlannedRouteDetectionSettingsSection: View {
    @Binding var settings: PlannedRouteDetectionSettings

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Near plan: \(Int(settings.nearPlanMeters)) m")
                Slider(value: $settings.nearPlanMeters, in: 2...8, step: 1)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Divergence threshold: \(Int(settings.divergenceThresholdMeters)) m")
                Slider(value: $settings.divergenceThresholdMeters, in: 4...15, step: 1)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Cooldown: \(Int(settings.cooldownSeconds)) s")
                Slider(value: $settings.cooldownSeconds, in: 3...30, step: 1)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Max GPS accuracy: \(Int(settings.maximumGPSAccuracyMeters)) m")
                Slider(value: $settings.maximumGPSAccuracyMeters, in: 10...40, step: 5)
            }
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
}
