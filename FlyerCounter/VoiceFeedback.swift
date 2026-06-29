import AVFoundation
import Foundation

@MainActor
enum VoiceFeedback {
    private static let synthesizer = AVSpeechSynthesizer()
    private static var lastSpokenCooldownSecond: Int?

    static func prepare() {
        configureAudioSession()
    }

    static func resetCooldownTracking() {
        lastSpokenCooldownSecond = nil
    }

    static func handle(evaluation: AutoFlyerEvaluation) {
        if let degrees = evaluation.countedTurnDeltaDegrees {
            lastSpokenCooldownSecond = nil
            speak("Flyer counted \(degrees) degrees")
            return
        }

        guard let remaining = evaluation.cooldownRemainingSeconds else { return }
        guard remaining != lastSpokenCooldownSecond else { return }

        lastSpokenCooldownSecond = remaining
        let unit = remaining == 1 ? "second" : "seconds"
        speak("\(remaining) \(unit)")
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
