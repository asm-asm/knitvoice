import AVFoundation

/// 録音中かどうかでカテゴリを切り替える。
/// 録音用（.playAndRecord）のままだと読み上げの音量が小さくなるので、マイクOFFの間は再生用（.playback）にする。
enum AudioSession {
    /// 他アプリの音楽と同時に使う（イヤホンボタンモードでは false。再生中アプリになる必要があるため）
    private static var allowMixing = true
    private static var recording = false

    static func configure(allowMixing: Bool) {
        self.allowMixing = allowMixing
        apply()
    }

    static func setRecording(_ recording: Bool) {
        guard self.recording != recording else { return }
        self.recording = recording
        apply()
    }

    private static func apply() {
        let session = AVAudioSession.sharedInstance()
        var options: AVAudioSession.CategoryOptions = []
        if allowMixing {
            options.insert(.mixWithOthers)
        }
        do {
            if recording {
                options.formUnion([.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP])
                try session.setCategory(.playAndRecord, mode: .default, options: options)
            } else {
                try session.setCategory(.playback, mode: .spokenAudio, options: options)
            }
            try session.setActive(true)
        } catch {
            print("AudioSession の設定に失敗: \(error)")
        }
    }
}
