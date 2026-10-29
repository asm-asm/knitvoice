import Foundation

/// 「○段目」の読み上げ方（アプリ設定）。
enum RowReadingStyle: String, Codable, CaseIterable, Identifiable {
    case full
    case numberOnly
    case silent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .full: return "段数を読む（「2段目」）"
        case .numberOnly: return "数字だけ（「2」）"
        case .silent: return "読み上げない"
        }
    }
}

/// 読み上げ・表示する日本語の文言。
enum Phrases {
    static let cannotUndo = "これ以上戻れません"
    static let finished = "全部終わりました"
    static let overTarget = "目標を超えています"

    static func step(_ event: StepEvent, style: RowReadingStyle) -> String? {
        switch event {
        case .finished: return finished
        case .overTarget: return overTarget
        case .setStarted(let n): return "\(n)セット目に入りました"
        case .repeatStarted(let n): return "\(n)回目"
        case .row(let n):
            switch style {
            case .full: return "\(n)段目"
            case .numberOnly: return "\(n)"
            case .silent: return nil
            }
        }
    }

    static func reminder(_ text: String) -> String { "次の段は\(text)です" }

    static func memo(_ text: String) -> String { "メモ、\(text)" }

    /// +1 時の読み上げをひとつにまとめる。読むものがなければ nil。
    static func increment(_ outcome: IncrementOutcome, style: RowReadingStyle, speakMemos: Bool) -> String? {
        var parts: [String] = []
        if let step = step(outcome.event, style: style) { parts.append(step) }
        parts += outcome.reminders.filter(\.speak).map { reminder($0.text) }
        if speakMemos { parts += outcome.memos.map { memo($0.text) } }
        return parts.isEmpty ? nil : parts.joined(separator: "。")
    }

    static func undo(completedRows: Int, config: CounterConfig) -> String {
        let p = CounterEngine.position(completedRows: completedRows, config: config)
        switch config.mode {
        case .simple:
            return "\(p.currentRow)段目に戻りました"
        case .set:
            return "\(p.set)セット目、\(p.repeatIndex)回目の\(p.rowInRepeat)段目に戻りました"
        }
    }

    /// 「今どこ」への返答。
    static func current(completedRows: Int, config: CounterConfig) -> String {
        if CounterEngine.isFinished(completedRows: completedRows, config: config) {
            return "\(finished)。通算\(completedRows)段完了です"
        }
        let p = CounterEngine.position(completedRows: completedRows, config: config)
        switch config.mode {
        case .simple:
            return "\(p.currentRow)段目です。通算\(completedRows)段完了"
        case .set:
            return "\(p.set)セット目、\(p.repeatIndex)回目の\(p.rowInRepeat)段目です。通算\(completedRows)段完了"
        }
    }

    /// 一覧・Now Playing・Watch用の短い位置表示（例：「2セット目 3回目 2/2段」）。
    static func positionSummary(completedRows: Int, config: CounterConfig) -> String {
        if CounterEngine.isFinished(completedRows: completedRows, config: config) {
            return "完成（通算\(completedRows)段）"
        }
        let p = CounterEngine.position(completedRows: completedRows, config: config)
        switch config.mode {
        case .simple:
            return "\(p.currentRow)段目"
        case .set:
            return "\(p.set)セット目 \(p.repeatIndex)回目 \(p.rowInRepeat)/\(config.safeRowsPerRepeat)段"
        }
    }
}
