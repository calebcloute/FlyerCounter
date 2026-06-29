import Combine
import Foundation
import SwiftUI

struct CompassTurnaroundSettings: Codable, Equatable {
    var turnaroundThresholdDegrees: Double = 150
    var cooldownSeconds: Double = 8
}

struct AutoFlyerSettings: Codable, Equatable {
    var isEnabled: Bool = false
    var turnaround = CompassTurnaroundSettings()
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
                "Uses compass heading change (turnaround detection) while a route is recording. " +
                "Manual +1 and -1 still work. Each auto count gives one vibration in the app, " +
                "or a notification on the lock screen."
            )
            .foregroundStyle(.secondary)
        }

        if store.settings.isEnabled {
            CompassTurnaroundSettingsSection(settings: $store.settings.turnaround)
        }
    }
}
