import AudioToolbox
import Foundation
import UIKit
import UserNotifications

enum AutoFlyerCountFeedback {
    private static let categoryIdentifier = "autoFlyerCount"

    static func prepare() {
        UNUserNotificationCenter.current().setNotificationCategories([
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

    static func playLongVibrationPulse() {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }

    static func postNotification(note: String?) async {
        let content = UNMutableNotificationContent()
        content.title = "Flyer counted"
        content.body = note ?? "Automatic flyer count recorded."
        content.sound = .default
        content.categoryIdentifier = categoryIdentifier
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: "auto-flyer-count-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        try? await UNUserNotificationCenter.current().add(request)
    }

    @MainActor
    static func deliver(note: String?) {
        if UIApplication.shared.applicationState == .active {
            playLongVibrationPulse()
        } else {
            Task {
                await postNotification(note: note)
            }
        }
    }
}

extension FlyerDropSource {
    var isAutomatic: Bool {
        switch self {
        case .manual:
            false
        case .autoBacktrack, .autoCompassTurnaround:
            true
        }
    }
}
