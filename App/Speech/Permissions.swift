import AVFoundation
import Speech

enum Permissions {
    static var allGranted: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
            && AVAudioApplication.shared.recordPermission == .granted
    }

    /// 音声認識 → マイクの順に許可を求める。両方許可されたら true。
    static func requestAll() async -> Bool {
        let speech = await requestSpeechRecognition()
        let microphone = await AVAudioApplication.requestRecordPermission()
        return speech && microphone
    }

    private static func requestSpeechRecognition() async -> Bool {
        if SFSpeechRecognizer.authorizationStatus() == .authorized { return true }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}
