import Combine
import Foundation
import SwiftUI

enum AutoFlyerCountingMethod: String, Codable, CaseIterable, Identifiable {
    case backtrackOverlap
    case compassTurnaround

    var id: String { rawValue }

    var label: String {
        switch self {
        case .backtrackOverlap:
            "Backtrack overlap (GPS walk direction)"
        case .compassTurnaround:
            "Turnaround (compass heading change)"
        }
    }

    var statusDescription: String {
        switch self {
        case .backtrackOverlap:
            "Watching for backtrack overlap while you walk."
        case .compassTurnaround:
            "Watching for sharp compass turnarounds while you walk."
        }
    }
}

struct BacktrackDetectionSettings: Codable, Equatable {
    var pathMatchToleranceMeters: Double = 12
    var minimumOverlapMeters: Double = 8
    var cooldownSeconds: Double = 8
}

struct CompassTurnaroundSettings: Codable, Equatable {
    var turnaroundThresholdDegrees: Double = 150
    var cooldownSeconds: Double = 8
}

struct AutoFlyerSettings: Codable, Equatable {
    var isEnabled: Bool = false
    var method: AutoFlyerCountingMethod = .backtrackOverlap
    var backtrack = BacktrackDetectionSettings()
    var compassTurnaround = CompassTurnaroundSettings()
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
                "Minimum overlap is how much shared path is required before counting."
            )
            .foregroundStyle(.secondary)
        }
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
                "Counts a flyer when you turn around sharply compared to where the phone was facing " +
                "a few seconds ago. Uses the device compass (not GPS movement). Hold the phone upright " +
                "in portrait with the top facing the direction you walk for best results. A turn onto a " +
                "driveway (~90°) won't count; turning back at the house (~180°) will."
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

            if store.settings.isEnabled {
                Picker("Method", selection: $store.settings.method) {
                    ForEach(AutoFlyerCountingMethod.allCases) { method in
                        Text(method.label).tag(method)
                    }
                }
            }
        } header: {
            Text("Automatic Flyer Counting")
        } footer: {
            Text(
                "Choose how flyers are counted automatically while a route is recording. Manual +1 and -1 still work. " +
                "Each auto count gives one vibration in the app, or a notification on the lock screen."
            )
            .foregroundStyle(.secondary)
        }

        if store.settings.isEnabled {
            switch store.settings.method {
            case .backtrackOverlap:
                BacktrackDetectionSettingsSection(settings: $store.settings.backtrack)
            case .compassTurnaround:
                CompassTurnaroundSettingsSection(settings: $store.settings.compassTurnaround)
            }
        }
    }
}
