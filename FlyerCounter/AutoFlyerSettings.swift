import Combine
import Foundation
import SwiftUI

struct BacktrackDetectionSettings: Codable, Equatable {
    var pathMatchToleranceMeters: Double = 12
    var minimumReverseDistanceMeters: Double = 15
    var minimumOverlapMeters: Double = 8
    var cooldownSeconds: Double = 8
}

struct AutoFlyerSettings: Codable, Equatable {
    var isEnabled: Bool = false
    var backtrack = BacktrackDetectionSettings()
}

enum AutoFlyerSettingsStorage {
    private static let storageKey = "autoFlyerSettings"

    static func load() -> AutoFlyerSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(AutoFlyerSettings.self, from: data) else {
            return AutoFlyerSettings()
        }
        return settings
    }

    static func save(_ settings: AutoFlyerSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
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

struct BacktrackDetectionSettingsSection: View {
    @Binding var settings: BacktrackDetectionSettings

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Path match tolerance: \(Int(settings.pathMatchToleranceMeters)) m")
                Slider(value: $settings.pathMatchToleranceMeters, in: 5...30, step: 1)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Minimum reverse distance: \(Int(settings.minimumReverseDistanceMeters)) m")
                Slider(value: $settings.minimumReverseDistanceMeters, in: 5...40, step: 1)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Minimum overlap: \(Int(settings.minimumOverlapMeters)) m")
                Slider(value: $settings.minimumOverlapMeters, in: 3...25, step: 1)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Cooldown: \(Int(settings.cooldownSeconds)) s")
                Slider(value: $settings.cooldownSeconds, in: 3...30, step: 1)
            }
        } header: {
            Text("Backtrack Overlap")
        } footer: {
            Text(
                "Counts a flyer when you walk back over your outbound path in the opposite direction. " +
                "Path match tolerance is how close the return path must be to the original. " +
                "Minimum reverse distance is how far you must walk back before a count can happen. " +
                "Minimum overlap is how much shared path is required."
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
            Text("Uses backtrack overlap detection while a route is recording. Manual +1 and -1 still work.")
                .foregroundStyle(.secondary)
        }

        if store.settings.isEnabled {
            BacktrackDetectionSettingsSection(settings: $store.settings.backtrack)
        }
    }
}
