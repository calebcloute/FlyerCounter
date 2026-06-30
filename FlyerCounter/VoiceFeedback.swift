import AVFoundation
import Foundation

@MainActor
enum VoiceFeedback {
    private static let synthesizer = AVSpeechSynthesizer()
    private static let speechDelegate = VoiceSpeechDelegate()
    private static var lastQueuedCooldownSecond: Int?
    private static var lastEstablishingQueueDate: Date?
    private static var isAnnouncingFlyerCount = false
    private static var announcementPreferences = VoiceAnnouncementSettings()
    private static let establishingWaitInterval: TimeInterval = 0.6
    private static let cooldownUtteranceDelay: TimeInterval = 0.85

    static func prepare() {
        speechDelegate.onFlyerAnnouncementFinished = {
            isAnnouncingFlyerCount = false
        }
        synthesizer.delegate = speechDelegate
        configureAudioSession()
    }

    static func resetCooldownTracking() {
        lastQueuedCooldownSecond = nil
        isAnnouncingFlyerCount = false
        lastEstablishingQueueDate = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    static func prepareForBackgroundPlayback() {
        configureAudioSession()
    }

    static func handle(
        evaluation: AutoFlyerEvaluation,
        preferences: VoiceAnnouncementSettings
    ) {
        announcementPreferences = preferences

        if evaluation.countedBacktrackOverlap == true {
            lastQueuedCooldownSecond = nil
            lastEstablishingQueueDate = nil
            guard preferences.speakFlyerCountedBacktrack else { return }
            speakFlyerCountedBacktrack()
            return
        }

        if let meters = evaluation.countedMetersFromPlan {
            lastQueuedCooldownSecond = nil
            lastEstablishingQueueDate = nil
            guard preferences.speakFlyerCountedPlannedRoute else { return }
            speakFlyerCountedFromPlan(meters: meters)
            return
        }

        if let degrees = evaluation.countedTurnDeltaDegrees {
            lastQueuedCooldownSecond = nil
            lastEstablishingQueueDate = nil
            guard preferences.speakFlyerCountedTurnaround else { return }
            speakFlyerCounted(degrees: degrees)
            return
        }

        if let remaining = evaluation.cooldownRemainingSeconds {
            if isAnnouncingFlyerCount { return }
            guard preferences.speakCooldownCountdown else { return }

            guard lastQueuedCooldownSecond == nil else { return }

            lastQueuedCooldownSecond = remaining
            lastEstablishingQueueDate = nil
            speakCooldownSequence(from: remaining)
            return
        }

        if evaluation.isEstablishingLookback {
            guard preferences.speakEstablishingWait else { return }
            guard !isAnnouncingFlyerCount else { return }

            queueEstablishingWaitsIfNeeded()
            return
        }

        lastEstablishingQueueDate = nil
    }

    private static func speakFlyerCounted(degrees: Int) {
        speakFlyerAnnouncement("Flyer counted \(degrees) degrees")
    }

    private static func speakFlyerCountedFromPlan(meters: Int) {
        speakFlyerAnnouncement("Flyer counted \(meters) meters from plan")
    }

    private static func speakFlyerCountedBacktrack() {
        speakFlyerAnnouncement("Flyer counted at backtrack")
    }

    private static func speakFlyerAnnouncement(_ text: String) {
        configureAudioSession()
        isAnnouncingFlyerCount = true

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    private static func speakCooldownSequence(from remaining: Int) {
        configureAudioSession()

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        guard remaining >= 1 else { return }

        for second in stride(from: remaining, through: 1, by: -1) {
            let utterance = AVSpeechUtterance(string: "\(second)")
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate
            if second != remaining {
                utterance.preUtteranceDelay = cooldownUtteranceDelay
            }
            synthesizer.speak(utterance)
        }
    }

    private static func queueEstablishingWaitsIfNeeded() {
        let now = Date()
        if let lastEstablishingQueueDate,
           now.timeIntervalSince(lastEstablishingQueueDate) < establishingWaitInterval {
            return
        }

        lastEstablishingQueueDate = now
        configureAudioSession()

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let burstCount = 4
        for index in 0..<burstCount {
            let utterance = AVSpeechUtterance(string: "wait")
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.3
            if index > 0 {
                utterance.preUtteranceDelay = establishingWaitInterval
            }
            synthesizer.speak(utterance)
        }
    }

    private static func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers, .mixWithOthers, .interruptSpokenAudioAndMixWithOthers]
            )
            try session.setActive(true, options: [])
        } catch {
            // Speech may still work in the foreground without a configured session.
        }
    }
}

@MainActor
private final class VoiceSpeechDelegate: NSObject, AVSpeechSynthesizerDelegate {
    var onFlyerAnnouncementFinished: (() -> Void)?

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finishFlyerAnnouncementIfNeeded(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finishFlyerAnnouncementIfNeeded(utterance)
    }

    private nonisolated func finishFlyerAnnouncementIfNeeded(_ utterance: AVSpeechUtterance) {
        guard utterance.speechString.hasPrefix("Flyer counted") else { return }

        Task { @MainActor in
            onFlyerAnnouncementFinished?()
        }
    }
}
