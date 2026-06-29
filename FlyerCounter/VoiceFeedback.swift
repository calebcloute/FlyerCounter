import AVFoundation
import Foundation

@MainActor
enum VoiceFeedback {
    private static let synthesizer = AVSpeechSynthesizer()
    private static let speechDelegate = VoiceSpeechDelegate()
    private static var lastSpokenCooldownSecond: Int?
    private static var establishingWaitTimer: Timer?
    private static var lastEstablishingWaitSpeakDate: Date?
    private static var isAnnouncingFlyerCount = false
    private static var announcementPreferences = VoiceAnnouncementSettings()
    private static let establishingWaitInterval: TimeInterval = 0.6

    static func prepare() {
        speechDelegate.onFlyerAnnouncementFinished = {
            isAnnouncingFlyerCount = false
        }
        synthesizer.delegate = speechDelegate
        configureAudioSession()
    }

    static func resetCooldownTracking() {
        lastSpokenCooldownSecond = nil
        isAnnouncingFlyerCount = false
        stopEstablishingWaitLoop()
    }

    static func handle(
        evaluation: AutoFlyerEvaluation,
        preferences: VoiceAnnouncementSettings
    ) {
        announcementPreferences = preferences

        if evaluation.countedBacktrackOverlap == true {
            stopEstablishingWaitLoop()
            lastSpokenCooldownSecond = nil
            guard preferences.speakFlyerCountedBacktrack else { return }
            speakFlyerCountedBacktrack()
            return
        }

        if let meters = evaluation.countedMetersFromPlan {
            stopEstablishingWaitLoop()
            lastSpokenCooldownSecond = nil
            guard preferences.speakFlyerCountedPlannedRoute else { return }
            speakFlyerCountedFromPlan(meters: meters)
            return
        }

        if let degrees = evaluation.countedTurnDeltaDegrees {
            stopEstablishingWaitLoop()
            lastSpokenCooldownSecond = nil
            guard preferences.speakFlyerCountedTurnaround else { return }
            speakFlyerCounted(degrees: degrees)
            return
        }

        if let remaining = evaluation.cooldownRemainingSeconds {
            stopEstablishingWaitLoop()
            if isAnnouncingFlyerCount { return }
            guard preferences.speakCooldownCountdown else { return }

            guard remaining != lastSpokenCooldownSecond else { return }

            lastSpokenCooldownSecond = remaining
            speakCooldown(remaining)
            return
        }

        if evaluation.isEstablishingLookback {
            guard preferences.speakEstablishingWait else {
                stopEstablishingWaitLoop()
                return
            }
            guard !isAnnouncingFlyerCount else { return }

            speakEstablishingWaitBurstIfDue()
            startEstablishingWaitLoopIfNeeded()
            return
        }

        stopEstablishingWaitLoop()
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

    private static func speakCooldown(_ remaining: Int) {
        configureAudioSession()

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: "\(remaining)")
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    private static func startEstablishingWaitLoopIfNeeded() {
        guard establishingWaitTimer == nil else { return }

        let timer = Timer(
            fire: Date().addingTimeInterval(establishingWaitInterval),
            interval: establishingWaitInterval,
            repeats: true
        ) { _ in
            Task { @MainActor in
                guard announcementPreferences.speakEstablishingWait else { return }
                guard !isAnnouncingFlyerCount else { return }
                speakEstablishingWaitBurstIfDue()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        establishingWaitTimer = timer
    }

    private static func stopEstablishingWaitLoop() {
        establishingWaitTimer?.invalidate()
        establishingWaitTimer = nil
        lastEstablishingWaitSpeakDate = nil
    }

    private static func speakEstablishingWaitBurstIfDue() {
        let now = Date()
        if let lastEstablishingWaitSpeakDate,
           now.timeIntervalSince(lastEstablishingWaitSpeakDate) < establishingWaitInterval {
            return
        }

        lastEstablishingWaitSpeakDate = now
        speakEstablishingWaitBurst()
    }

    private static func speakEstablishingWaitBurst() {
        configureAudioSession()

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: "wait")
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.3
        synthesizer.speak(utterance)
    }

    private static func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
            try session.setActive(true)
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
