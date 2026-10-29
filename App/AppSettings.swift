import Foundation

/// アプリ設定（UserDefaults に保存）。
@Observable
final class AppSettings {
    private enum Key {
        static let rowReadingStyle = "rowReadingStyle"
        static let speakMemos = "speakMemos"
        static let speechEnabled = "speechEnabled"
        static let earphoneButtonsEnabled = "earphoneButtonsEnabled"
        static let commandDebounceInterval = "commandDebounceInterval"
        static let hasSeenPermissionIntro = "hasSeenPermissionIntro"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var rowReadingStyle: RowReadingStyle {
        didSet { defaults.set(rowReadingStyle.rawValue, forKey: Key.rowReadingStyle) }
    }
    /// メモを読み上げる
    var speakMemos: Bool {
        didSet { defaults.set(speakMemos, forKey: Key.speakMemos) }
    }
    /// カウンター画面の読み上げON/OFF
    var speechEnabled: Bool {
        didSet { defaults.set(speechEnabled, forKey: Key.speechEnabled) }
    }
    /// イヤホンのボタンでカウント（デフォルトOFF）
    var earphoneButtonsEnabled: Bool {
        didSet { defaults.set(earphoneButtonsEnabled, forKey: Key.earphoneButtonsEnabled) }
    }
    /// 同じ音声コマンドの連続を無視する秒数
    var commandDebounceInterval: Double {
        didSet { defaults.set(commandDebounceInterval, forKey: Key.commandDebounceInterval) }
    }
    var hasSeenPermissionIntro: Bool {
        didSet { defaults.set(hasSeenPermissionIntro, forKey: Key.hasSeenPermissionIntro) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        rowReadingStyle = RowReadingStyle(rawValue: defaults.string(forKey: Key.rowReadingStyle) ?? "") ?? .full
        speakMemos = defaults.object(forKey: Key.speakMemos) as? Bool ?? true
        speechEnabled = defaults.object(forKey: Key.speechEnabled) as? Bool ?? true
        earphoneButtonsEnabled = defaults.bool(forKey: Key.earphoneButtonsEnabled)
        commandDebounceInterval = defaults.object(forKey: Key.commandDebounceInterval) as? Double
            ?? CommandDebouncer.defaultInterval
        hasSeenPermissionIntro = defaults.bool(forKey: Key.hasSeenPermissionIntro)
    }
}
