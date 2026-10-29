import AVFoundation
import Speech

enum RecognitionUpdate {
    case partial(String)
    case final(String)
    /// 認識タスクを作り直した（テキストは空から始まる）
    case restarted
    case failed(Error)
}

/// 音声認識の抽象。将来 iOS 26 の SpeechAnalyzer / SpeechTranscriber に差し替えられるようにする。
@MainActor
protocol SpeechRecognitionEngine: AnyObject {
    var onUpdate: (@MainActor (RecognitionUpdate) -> Void)? { get set }
    var contextualStrings: [String] { get set }
    var isRunning: Bool { get }
    func start() throws
    func stop()
    /// 認識テキストが溜まり続けないよう、現在のタスクを捨てて新しく始める
    func restartTask()
}

enum SpeechEngineError: LocalizedError {
    case recognizerUnavailable

    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable: return "日本語の音声認識が使えません"
        }
    }
}

/// SFSpeechRecognizer（ja-JP）による実装。
@MainActor
final class AppleSpeechRecognitionEngine: SpeechRecognitionEngine {
    /// 一定時間でタスクを作り直す（Appleの1分制限より手前）
    static let maxTaskDuration: TimeInterval = 50
    static let errorRetryDelay: TimeInterval = 0.5
    /// エコーキャンセル。有効にすると読み上げの音量がかなり下がるため既定はOFF
    /// （自分の読み上げを拾う対策は SpeechEchoGate で行う）
    var useVoiceProcessing = false

    var onUpdate: (@MainActor (RecognitionUpdate) -> Void)?
    var contextualStrings: [String] = []
    private(set) var isRunning = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP"))
    private let audioEngine = AVAudioEngine()
    private let sink = BufferSink()
    private var task: SFSpeechRecognitionTask?
    /// 古いタスクからの遅れた結果を捨てるための世代番号
    private var generation = 0
    private var rotationTimer: Timer?
    private var configurationObserver: NSObjectProtocol?

    func start() throws {
        guard !isRunning else { return }
        guard let recognizer, recognizer.isAvailable else { throw SpeechEngineError.recognizerUnavailable }
        try startAudio()
        isRunning = true
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleConfigurationChange() }
        }
        startTask()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        rotationTimer?.invalidate()
        rotationTimer = nil
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        configurationObserver = nil
        generation += 1
        task?.cancel()
        task = nil
        sink.replace(with: nil)?.endAudio()
        stopAudio()
    }

    func restartTask() {
        guard isRunning else { return }
        startTask()
    }

    // MARK: - Audio

    private func startAudio() throws {
        let input = audioEngine.inputNode
        if useVoiceProcessing {
            try? input.setVoiceProcessingEnabled(true)
        }
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.makeTapBlock(sink: sink))
        audioEngine.prepare()
        try audioEngine.start()
    }

    private func stopAudio() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        if useVoiceProcessing {
            try? audioEngine.inputNode.setVoiceProcessingEnabled(false)
        }
    }

    /// AirPodsの接続などで入力が変わったら作り直す
    private func handleConfigurationChange() {
        guard isRunning else { return }
        stopAudio()
        do {
            try startAudio()
            startTask()
        } catch {
            stop()
            onUpdate?(.failed(error))
        }
    }

    // MARK: - Recognition task

    private func startTask() {
        guard let recognizer else { return }
        generation += 1
        let current = generation
        task?.cancel()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.contextualStrings = contextualStrings
        request.addsPunctuation = false
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        sink.replace(with: request)?.endAudio()

        task = recognizer.recognitionTask(
            with: request,
            resultHandler: Self.makeResultHandler(generation: current, owner: self)
        )
        onUpdate?(.restarted)

        rotationTimer?.invalidate()
        rotationTimer = Timer.scheduledTimer(withTimeInterval: Self.maxTaskDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.restartTask() }
        }
    }

    private func receive(generation received: Int, text: String?, isFinal: Bool, error: Error?) {
        guard received == generation, isRunning else { return }
        if let text {
            onUpdate?(isFinal ? .final(text) : .partial(text))
            // onUpdate 内で作り直されていなければ、final 後に作り直す
            if isFinal && received == generation {
                startTask()
            }
            return
        }
        if let error {
            generation += 1
            onUpdate?(.failed(error))
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(Self.errorRetryDelay))
                self?.restartTask()
            }
        }
    }

    // 以下はオーディオスレッド・認識スレッドから呼ばれるので、メインアクターに縛られないクロージャを作る

    nonisolated private static func makeTapBlock(sink: BufferSink) -> AVAudioNodeTapBlock {
        { buffer, _ in sink.append(buffer) }
    }

    nonisolated private static func makeResultHandler(
        generation: Int,
        owner: AppleSpeechRecognitionEngine
    ) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { [weak owner] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            Task { @MainActor in
                owner?.receive(generation: generation, text: text, isFinal: isFinal, error: error)
            }
        }
    }
}

/// オーディオスレッドから現在のリクエストへバッファを渡す。
private final class BufferSink: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let request = request
        lock.unlock()
        request?.append(buffer)
    }

    /// 新しいリクエストに差し替え、古いものを返す。
    @discardableResult
    func replace(with newRequest: SFSpeechAudioBufferRecognitionRequest?) -> SFSpeechAudioBufferRecognitionRequest? {
        lock.lock()
        defer { lock.unlock() }
        let old = request
        request = newRequest
        return old
    }
}
