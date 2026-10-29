import AVFoundation

/// 日本語の読み上げ。読み上げ中かどうかを音声認識側の誤検知対策に使う。
@MainActor
@Observable
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    /// 少し高めの声にする（1.0 が標準、0.5〜2.0）
    static let pitch: Float = 1.2

    private(set) var isSpeaking = false
    private(set) var lastFinishedAt: Date?

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var currentUtterance: AVSpeechUtterance?
    @ObservationIgnored private let voice = Speaker.bestJapaneseVoice()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = Self.pitch
        utterance.volume = 1.0
        currentUtterance = utterance
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// 端末に入っている日本語の声のうち、いちばん高品質なもの（プレミアム → 拡張 → 標準）。
    /// 「設定 → アクセシビリティ → 読み上げコンテンツ → 声 → 日本語」で追加した声も使われる。
    private static func bestJapaneseVoice() -> AVSpeechSynthesisVoice? {
        let japanese = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "ja-JP" }
        return japanese.max { $0.quality.rawValue < $1.quality.rawValue }
            ?? AVSpeechSynthesisVoice(language: "ja-JP")
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished(utterance) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.finished(utterance) }
    }

    private func finished(_ utterance: AVSpeechUtterance) {
        // 新しい読み上げで中断された古い発話の通知は無視する
        guard utterance === currentUtterance else { return }
        currentUtterance = nil
        isSpeaking = false
        lastFinishedAt = Date()
    }
}
