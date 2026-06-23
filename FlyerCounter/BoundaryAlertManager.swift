import Foundation
import UIKit
import UserNotifications

enum BoundaryNotificationScheduler {
    private static let categoryIdentifier = "boundaryAlert"

    static func prepare() {
        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: categoryIdentifier,
                actions: [],
                intentIdentifiers: [],
                options: []
            ),
        ])
    }

    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func postPulse() async {
        let content = UNMutableNotificationContent()
        content.title = "Area boundary"
        content.body = "You are on or outside the boundary."
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: "boundary-pulse-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    static func cancelPending() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}

@MainActor
final class BoundaryAlertManager {
    private var pulseTask: Task<Void, Never>?
    private(set) var isAlerting = false
    private var pulseIntervalSeconds: TimeInterval = 3
    private var vibrateInBackground = true

    func apply(settings: BoundaryAlertSettings) {
        pulseIntervalSeconds = settings.pulseIntervalSeconds
        vibrateInBackground = settings.vibrateInBackground

        if !settings.isEnabled {
            stop()
        }
    }

    func update(shouldAlert: Bool, settings: BoundaryAlertSettings) {
        apply(settings: settings)

        guard settings.isEnabled else {
            stop()
            return
        }

        if shouldAlert {
            guard !isAlerting else { return }
            startPulsing()
        } else {
            stop()
        }
    }

    func stop() {
        isAlerting = false
        pulseTask?.cancel()
        pulseTask = nil
        BoundaryNotificationScheduler.cancelPending()
    }

    private func startPulsing() {
        stop()
        isAlerting = true

        pulseTask = Task {
            while !Task.isCancelled {
                await deliverPulse()
                do {
                    try await Task.sleep(for: .seconds(pulseIntervalSeconds))
                } catch {
                    break
                }
            }
        }
    }

    private var isAppInBackground: Bool {
        UIApplication.shared.applicationState != .active
    }

    private func deliverPulse() async {
        if isAppInBackground {
            guard vibrateInBackground else { return }
            await BoundaryNotificationScheduler.postPulse()
        } else {
            BoundaryProximity.playVibrationPulsePair()
        }
    }
}
