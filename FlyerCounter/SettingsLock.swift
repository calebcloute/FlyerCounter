import Combine
import CryptoKit
import Foundation
import SwiftUI

struct CountingMethodSettingsSnapshot: Codable, Equatable {
    var method: AutoFlyerCountingMethod
    var turnaround: CompassTurnaroundSettings?
    var pathBacktrack: PathBacktrackSettings?
    var plannedRoute: PlannedRouteDetectionSettings?

    init(from settings: AutoFlyerSettings) {
        method = settings.method
        switch settings.method {
        case .compassTurnaround:
            turnaround = settings.turnaround
            pathBacktrack = nil
            plannedRoute = nil
        case .pathBacktrack:
            turnaround = nil
            pathBacktrack = settings.pathBacktrack
            plannedRoute = nil
        case .plannedRouteDivergence:
            turnaround = nil
            pathBacktrack = nil
            plannedRoute = settings.plannedRoute
        }
    }

    func applied(to settings: AutoFlyerSettings) -> AutoFlyerSettings {
        var updated = settings
        updated.method = method
        switch method {
        case .compassTurnaround:
            if let turnaround { updated.turnaround = turnaround }
        case .pathBacktrack:
            if let pathBacktrack { updated.pathBacktrack = pathBacktrack }
        case .plannedRouteDivergence:
            if let plannedRoute { updated.plannedRoute = plannedRoute }
        }
        return updated
    }

    var summaryLines: [String] {
        switch method {
        case .compassTurnaround:
            guard let turnaround else { return ["Method: \(method.title)"] }
            return [
                "Method: \(method.title)",
                "Turn threshold: \(Int(turnaround.turnaroundThresholdDegrees))°",
                "Cooldown: \(Int(turnaround.cooldownSeconds)) s"
            ]
        case .pathBacktrack:
            guard let pathBacktrack else { return ["Method: \(method.title)"] }
            return [
                "Method: \(method.title)",
                "Distance from path line: \(Int(pathBacktrack.overlapRadiusMeters)) m",
                "Min path behind furthest point: \(Int(pathBacktrack.minBacktrackSeparationMeters)) m",
                "Cooldown: \(Int(pathBacktrack.cooldownSeconds)) s",
                "Max GPS accuracy: \(Int(pathBacktrack.maximumGPSAccuracyMeters)) m"
            ]
        case .plannedRouteDivergence:
            guard let plannedRoute else { return ["Method: \(method.title)"] }
            return [
                "Method: \(method.title)",
                "Near plan: \(Int(plannedRoute.nearPlanMeters)) m",
                "Divergence threshold: \(Int(plannedRoute.divergenceThresholdMeters)) m",
                "Cooldown: \(Int(plannedRoute.cooldownSeconds)) s",
                "Max GPS accuracy: \(Int(plannedRoute.maximumGPSAccuracyMeters)) m"
            ]
        }
    }
}

enum SettingsLockStorage {
    private static let storageKey = "settingsLockState"

    struct PersistedState: Codable {
        var isLocked: Bool
        var pinHash: String?
        var lockedSnapshot: CountingMethodSettingsSnapshot?
    }

    static func load() -> PersistedState {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let state = try? JSONDecoder().decode(PersistedState.self, from: data) else {
            return PersistedState(isLocked: false, pinHash: nil, lockedSnapshot: nil)
        }
        return state
    }

    static func save(_ state: PersistedState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

enum SettingsLockPIN {
    static let requiredLength = 4

    static func hash(_ pin: String) -> String {
        let digest = SHA256.hash(data: Data(pin.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func isValidFormat(_ pin: String) -> Bool {
        pin.count == requiredLength && pin.allSatisfy(\.isNumber)
    }
}

@MainActor
final class SettingsLockStore: ObservableObject {
    @Published private(set) var isLocked = false
    @Published private(set) var lockedSnapshot: CountingMethodSettingsSnapshot?

    private var pinHash: String?

    init() {
        let state = SettingsLockStorage.load()
        isLocked = state.isLocked
        pinHash = state.pinHash
        lockedSnapshot = state.lockedSnapshot
    }

    var hasPIN: Bool {
        pinHash != nil
    }

    func enforcedAutoFlyerSettings(_ settings: AutoFlyerSettings) -> AutoFlyerSettings {
        guard isLocked, let lockedSnapshot else { return settings }
        return lockedSnapshot.applied(to: settings)
    }

    @discardableResult
    func lock(snapshot: AutoFlyerSettings, pin: String) -> String? {
        guard SettingsLockPIN.isValidFormat(pin) else {
            return "Enter a 4-digit PIN."
        }

        let countingSnapshot = CountingMethodSettingsSnapshot(from: snapshot)
        pinHash = SettingsLockPIN.hash(pin)
        lockedSnapshot = countingSnapshot
        isLocked = true
        persist()
        return nil
    }

    @discardableResult
    func unlock(pin: String) -> String? {
        guard let pinHash else {
            isLocked = false
            lockedSnapshot = nil
            persist()
            return nil
        }

        guard SettingsLockPIN.hash(pin) == pinHash else {
            return "Incorrect PIN."
        }

        isLocked = false
        persist()
        return nil
    }

    @discardableResult
    func changePIN(currentPIN: String, newPIN: String) -> String? {
        guard let pinHash else { return "No PIN is set." }
        guard SettingsLockPIN.hash(currentPIN) == pinHash else {
            return "Current PIN is incorrect."
        }
        guard SettingsLockPIN.isValidFormat(newPIN) else {
            return "New PIN must be 4 digits."
        }

        self.pinHash = SettingsLockPIN.hash(newPIN)
        persist()
        return nil
    }

    private func persist() {
        SettingsLockStorage.save(
            SettingsLockStorage.PersistedState(
                isLocked: isLocked,
                pinHash: pinHash,
                lockedSnapshot: lockedSnapshot
            )
        )
    }
}

struct SettingsLockSection: View {
    @ObservedObject var settingsLockStore: SettingsLockStore
    @ObservedObject var autoFlyerSettingsStore: AutoFlyerSettingsStore

    @State private var showLockSheet = false
    @State private var showUnlockSheet = false
    @State private var showChangePINSheet = false

    var body: some View {
        Section {
            if settingsLockStore.isLocked {
                Label("Counting method settings are locked", systemImage: "lock.fill")
                    .foregroundStyle(.orange)

                if let snapshot = settingsLockStore.lockedSnapshot {
                    ForEach(snapshot.summaryLines, id: \.self) { line in
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(line.hasPrefix("Method:") ? .primary : .secondary)
                    }
                }

                Button("Unlock counting method settings") {
                    showUnlockSheet = true
                }
            } else {
                Label("Counting method settings are unlocked", systemImage: "lock.open")
                    .foregroundStyle(.secondary)

                Button("Lock counting method settings…") {
                    showLockSheet = true
                }
            }

            if settingsLockStore.hasPIN, !settingsLockStore.isLocked {
                Button("Change PIN") {
                    showChangePINSheet = true
                }
            }
        } header: {
            Text("Lock Counting Method Settings")
        } footer: {
            Text(
                "Locks your counting method and its threshold sliders " +
                "(for example, turnaround with a 12 s cooldown). " +
                "Set your preferred values first, then lock them. " +
                "Other settings in this tab stay editable."
            )
            .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showLockSheet) {
            SettingsLockPINSheet(
                title: "Lock Counting Method Settings",
                message: "This saves your current counting method and its thresholds. They cannot change until you unlock with this PIN.",
                confirmPIN: true
            ) { pin in
                let error = settingsLockStore.lock(
                    snapshot: autoFlyerSettingsStore.settings,
                    pin: pin
                )
                if error == nil {
                    autoFlyerSettingsStore.applySettingsLock(from: settingsLockStore)
                }
                return error
            }
        }
        .sheet(isPresented: $showUnlockSheet) {
            SettingsLockPINSheet(
                title: "Unlock Counting Method Settings",
                message: "Enter your PIN to change the counting method and its thresholds again.",
                confirmPIN: false
            ) { pin in
                settingsLockStore.unlock(pin: pin)
            }
        }
        .sheet(isPresented: $showChangePINSheet) {
            SettingsChangePINSheet(settingsLockStore: settingsLockStore)
        }
    }
}

private struct SettingsLockPINSheet: View {
    let title: String
    let message: String
    let confirmPIN: Bool
    let onSubmit: (String) -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var pin = ""
    @State private var confirm = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    SecureField("4-digit PIN", text: $pin)
                        .keyboardType(.numberPad)
                        .onChange(of: pin) { _, newValue in
                            pin = String(newValue.filter(\.isNumber).prefix(SettingsLockPIN.requiredLength))
                        }

                    if confirmPIN {
                        SecureField("Confirm PIN", text: $confirm)
                            .keyboardType(.numberPad)
                            .onChange(of: confirm) { _, newValue in
                                confirm = String(newValue.filter(\.isNumber).prefix(SettingsLockPIN.requiredLength))
                            }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmPIN ? "Lock" : "Unlock") {
                        submit()
                    }
                    .disabled(!canSubmit)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var canSubmit: Bool {
        guard SettingsLockPIN.isValidFormat(pin) else { return false }
        if confirmPIN {
            return pin == confirm
        }
        return true
    }

    private func submit() {
        if confirmPIN, pin != confirm {
            errorMessage = "PINs do not match."
            return
        }

        if let error = onSubmit(pin) {
            errorMessage = error
            return
        }

        dismiss()
    }
}

private struct SettingsChangePINSheet: View {
    @ObservedObject var settingsLockStore: SettingsLockStore
    @Environment(\.dismiss) private var dismiss

    @State private var currentPIN = ""
    @State private var newPIN = ""
    @State private var confirmPIN = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Current PIN", text: $currentPIN)
                        .keyboardType(.numberPad)
                        .onChange(of: currentPIN) { _, newValue in
                            currentPIN = String(newValue.filter(\.isNumber).prefix(SettingsLockPIN.requiredLength))
                        }

                    SecureField("New PIN", text: $newPIN)
                        .keyboardType(.numberPad)
                        .onChange(of: newPIN) { _, newValue in
                            newPIN = String(newValue.filter(\.isNumber).prefix(SettingsLockPIN.requiredLength))
                        }

                    SecureField("Confirm new PIN", text: $confirmPIN)
                        .keyboardType(.numberPad)
                        .onChange(of: confirmPIN) { _, newValue in
                            confirmPIN = String(newValue.filter(\.isNumber).prefix(SettingsLockPIN.requiredLength))
                        }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Change PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var canSave: Bool {
        SettingsLockPIN.isValidFormat(currentPIN)
            && SettingsLockPIN.isValidFormat(newPIN)
            && newPIN == confirmPIN
    }

    private func save() {
        if let error = settingsLockStore.changePIN(currentPIN: currentPIN, newPIN: newPIN) {
            errorMessage = error
            return
        }
        dismiss()
    }
}
