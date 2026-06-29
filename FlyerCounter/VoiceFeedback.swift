import AVFoundation
import Foundation

@MainActor
enum VoiceFeedback {
    private static let synthesizer = AVSpeechSynthesizer()
    private static var lastSpokenCooldownSecond: Int?
    private static var establishingWaitTimer: Timer?
    private static var lastEstablishingWaitSpeakDate: Date?
    private static let establishingWaitInterval: TimeInterval = 0.6

    static func prepare() {
        configureAudioSession()
    }

    static func resetCooldownTracking() {
        lastSpokenCooldownSecond = nil
        stopEstablishingWaitLoop()
    }

    static func handle(evaluation: AutoFlyerEvaluation) {
        if let degrees = evaluation.countedTurnDeltaDegrees {
            stopEstablishingWaitLoop()
            lastSpokenCooldownSecond = nil
            speak("Flyer counted \(degrees) degrees")
            return
        }

        if let remaining = evaluation.cooldownRemainingSeconds {
            stopEstablishingWaitLoop()
            guard remaining != lastSpokenCooldownSecond else { return }

            lastSpokenCooldownSecond = remaining
            speak("\(remaining)")
            return
        }

        if evaluation.isEstablishingLookback {
            speakEstablishingWaitBurstIfDue()
            startEstablishingWaitLoopIfNeeded()
            return
        }

        stopEstablishingWaitLoop()
    }

    private static func startEstablishingWaitLoopIfNeeded() {
        guard establishingWaitTimer == nil else { return }

        let timer = Timer(
            fire: Date().addingTimeInterval(establishingWaitInterval),
            interval: establishingWaitInterval,
            repeats: true
        ) { _ in
            Task { @MainActor in
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

    private static func speak(_ text: String) {
        configureAudioSession()

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }
}
