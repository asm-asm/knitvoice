import Foundation

/// 認識テキスト → コマンドの変換。二重カウント・誤検知対策をまとめて行う。
@MainActor
@Observable
final class VoiceController {
    enum State: Equatable {
        case off
        case listening
        case failed(String)
    }

    private(set) var state: State = .off
    /// 画面下に出す「何て聞こえているか」
    private(set) var lastHeard = ""

    @ObservationIgnored var onCommand: (@MainActor (VoiceCommand) -> Void)?
    @ObservationIgnored private let engine: SpeechRecognitionEngine
    @ObservationIgnored private let matcher = VoiceCommandMatcher()
    @ObservationIgnored private var cursor = TranscriptCursor()
    @ObservationIgnored private var debouncer = CommandDebouncer()
    @ObservationIgnored private weak var speaker: Speaker?

    init(speaker: Speaker?, engine: SpeechRecognitionEngine? = nil) {
        self.speaker = speaker
        self.engine = engine ?? AppleSpeechRecognitionEngine()
    }

    var isListening: Bool { state == .listening }

    var debounceInterval: TimeInterval {
        get { debouncer.interval }
        set { debouncer.interval = newValue }
    }

    func start() async {
        guard !isListening else { return }
        guard await Permissions.requestAll() else {
            state = .failed("マイクと音声認識の許可が必要です（設定アプリで変更できます）")
            return
        }
        engine.contextualStrings = matcher.contextualStrings
        engine.onUpdate = { [weak self] update in self?.handle(update) }
        AudioSession.setRecording(true)
        do {
            try engine.start()
            state = .listening
        } catch {
            AudioSession.setRecording(false)
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        engine.stop()
        cursor.reset()
        // マイクOFFの間は再生用のカテゴリに戻して、読み上げの音量を大きくする
        AudioSession.setRecording(false)
        if isListening { state = .off }
    }

    private func handle(_ update: RecognitionUpdate) {
        switch update {
        case .restarted:
            cursor.reset()
        case .failed:
            // エンジン側で作り直すので状態は変えない。完全に止まった場合だけ反映
            if !engine.isRunning { state = .failed("音声認識が停止しました") }
        case .partial(let text), .final(let text):
            if !text.isEmpty { lastHeard = text }
            // 読み上げ中（と終了後少し）は自分の声を拾わないよう、判定せず処理済みにする
            if SpeechEchoGate.shouldIgnore(
                isSpeaking: speaker?.isSpeaking ?? false,
                lastFinishedAt: speaker?.lastFinishedAt,
                now: Date()
            ) {
                cursor.consumeAll(text)
                return
            }
            guard let command = cursor.nextCommand(in: text, matcher: matcher) else { return }
            if debouncer.shouldAccept(command, at: Date()) {
                onCommand?(command)
            }
            engine.restartTask()
        }
    }
}
