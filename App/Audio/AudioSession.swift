import AVFoundation

enum AudioSession {
    /// allowMixing：他アプリの音楽と同時に使う（イヤホンボタンモードでは false。再生中アプリになる必要があるため）
    static func configure(allowMixing: Bool) {
        var options: AVAudioSession.CategoryOptions = [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
        if allowMixing {
            options.insert(.mixWithOthers)
        }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: options)
            try session.setActive(true)
        } catch {
            print("AudioSession の設定に失敗: \(error)")
        }
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
