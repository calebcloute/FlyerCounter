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

    static func handle(evaluation: AutoFlyerEvaluation) {
        if let degrees = evaluation.countedTurnDeltaDegrees {
            stopEstablishingWaitLoop()
            lastSpokenCooldownSecond = nil
            speakFlyerCounted(degrees: degrees)
            return
        }

        if let remaining = evaluation.cooldownRemainingSeconds {
            stopEstablishingWaitLoop()
            if isAnnouncingFlyerCount { return }

            guard remaining != lastSpokenCooldownSecond else { return }

            lastSpokenCooldownSecond = remaining
            speakCooldown(remaining)
            return
        }

        if evaluation.isEstablishingLookback {
            guard !isAnnouncingFlyerCount else { return }

            speakEstablishingWaitBurstIfDue()
            startEstablishingWaitLoopIfNeeded()
            return
        }

        stopEstablishingWaitLoop()
    }

    private static func speakFlyerCounted(degrees: Int) {
        configureAudioSession()
        isAnnouncingFlyerCount = true

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: "Flyer counted \(degrees) degrees")
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
