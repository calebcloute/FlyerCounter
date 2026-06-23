import Combine
import Foundation
import SwiftUI

struct BoundaryAlertSettings: Codable, Equatable {
    var isEnabled: Bool = true
    /// Maximum distance from the boundary line that still counts as "on the edge."
    var edgeThresholdMeters: Double = 4
    /// Seconds between double-vibration bursts while on or outside the boundary.
    var pulseIntervalSeconds: Double = 3
    /// Ignore GPS fixes less accurate than this when checking the boundary.
    var maximumGPSAccuracyMeters: Double = 40
    /// On the lock screen, send notifications that vibrate (requires notification permission).
    var vibrateInBackground: Bool = true
}

enum BoundaryAlertSettingsStorage {
    private static let storageKey = "boundaryAlertSettings"

    static func load() -> BoundaryAlertSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let settings = try? JSONDecoder().decode(BoundaryAlertSettings.self, from: data) else {
            return BoundaryAlertSettings()
        }
        return settings
    }

    static func save(_ settings: BoundaryAlertSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

@MainActor
final class BoundaryAlertSettingsStore: ObservableObject {
    @Published var settings: BoundaryAlertSettings {
        didSet {
            BoundaryAlertSettingsStorage.save(settings)
        }
    }

    init() {
        settings = BoundaryAlertSettingsStorage.load()
    }
}

struct BoundaryAlertSettingsSection: View {
    @ObservedObject var store: BoundaryAlertSettingsStore

    var body: some View {
        Section {
            Toggle("Boundary vibration alerts", isOn: $store.settings.isEnabled)
        } footer: {
            Text(
                "Vibrates when you reach the edge of an active area map overlay or step outside it. " +
                "Select a map overlay on the Route Tracking tab. Alerts stop when you move back inside " +
                "the area or clear the overlay."
            )
            .foregroundStyle(.secondary)
        }

        if store.settings.isEnabled {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Edge threshold: \(edgeThresholdLabel)")
                    Slider(value: $store.settings.edgeThresholdMeters, in: 2...12, step: 1)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Pulse interval: \(Int(store.settings.pulseIntervalSeconds)) s")
                    Slider(value: $store.settings.pulseIntervalSeconds, in: 2...10, step: 1)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Max GPS accuracy: \(Int(store.settings.maximumGPSAccuracyMeters)) m")
                    Slider(value: $store.settings.maximumGPSAccuracyMeters, in: 15...60, step: 5)
                }

                Toggle("Vibrate on lock screen", isOn: $store.settings.vibrateInBackground)
            } header: {
                Text("Boundary Alerts")
            } footer: {
                Text(
                    "Edge threshold is how close you must be to the boundary line before alerting starts — " +
                    "not a early warning from far away. Two vibrations fire, then the app waits for the pulse " +
                    "interval before repeating. While the app is open, only vibration is used. On the lock screen, " +
                    "each pulse pair is delivered as a notification (iOS does not allow silent background vibration)."
                )
                .foregroundStyle(.secondary)
            }
        }
    }

    private var edgeThresholdLabel: String {
        let meters = Int(store.settings.edgeThresholdMeters)
        let feet = Int(store.settings.edgeThresholdMeters * 3.28084)
        return "\(meters) m (~\(feet) ft)"
    }
}
