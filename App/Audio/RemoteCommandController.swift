import AVFoundation
import MediaPlayer
import UIKit

/// イヤホンのボタン（MPRemoteCommandCenter）でカウントする。
/// リモートコマンドを受けるには「再生中アプリ」になる必要があるため、無音をループ再生する。
@MainActor
final class RemoteCommandController {
    var onIncrement: (@MainActor () -> Void)?
    var onDecrement: (@MainActor () -> Void)?
    private(set) var isEnabled = false

    private var player: AVAudioPlayer?
    private var registrations: [(command: MPRemoteCommand, token: Any)] = []
    /// 有効にした画面。作り直しで古い画面が後から disable しても止めないため
    private weak var owner: AnyObject?

    func enable(owner: AnyObject) {
        self.owner = owner
        guard !isEnabled else { return }
        isEnabled = true

        if let player = try? AVAudioPlayer(data: SilentAudio.wavData()) {
            player.numberOfLoops = -1
            player.volume = 0.01
            player.play()
            self.player = player
        }

        let center = MPRemoteCommandCenter.shared()
        for command in [center.togglePlayPauseCommand, center.playCommand, center.pauseCommand, center.nextTrackCommand] {
            register(command) { [weak self] in self?.onIncrement?() }
        }
        register(center.previousTrackCommand) { [weak self] in self?.onDecrement?() }
        center.changePlaybackPositionCommand.isEnabled = false
        UIApplication.shared.beginReceivingRemoteControlEvents()
    }

    func disable(owner: AnyObject) {
        guard isEnabled, self.owner == nil || self.owner === owner else { return }
        isEnabled = false
        self.owner = nil
        for registration in registrations {
            registration.command.removeTarget(registration.token)
            registration.command.isEnabled = false
        }
        registrations.removeAll()
        player?.stop()
        player = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        UIApplication.shared.endReceivingRemoteControlEvents()
    }

    /// ロック画面・コントロールセンターの再生中表示にプロジェクト名と現在位置を出す。
    func updateNowPlaying(title: String, detail: String) {
        guard isEnabled else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: detail,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
        ]
    }

    private func register(_ command: MPRemoteCommand, action: @escaping @MainActor () -> Void) {
        command.isEnabled = true
        let token = command.addTarget { _ in
            Task { @MainActor in action() }
            return .success
        }
        registrations.append((command, token))
    }
}

/// 無音のWAV（16bit モノラル）をメモリ上で作る。
enum SilentAudio {
    static func wavData(seconds: Double = 1, sampleRate: Int = 8000) -> Data {
        let dataSize = Int(Double(sampleRate) * seconds) * 2
        var data = Data()
        func append(_ string: String) { data.append(contentsOf: Array(string.utf8)) }
        func append32(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func append16(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }

        append("RIFF")
        append32(UInt32(36 + dataSize))
        append("WAVE")
        append("fmt ")
        append32(16)                       // fmt チャンクサイズ
        append16(1)                        // PCM
        append16(1)                        // モノラル
        append32(UInt32(sampleRate))
        append32(UInt32(sampleRate * 2))   // バイトレート
        append16(2)                        // ブロックサイズ
        append16(16)                       // ビット深度
        append("data")
        append32(UInt32(dataSize))
        data.append(Data(count: dataSize))
        return data
    }
}
