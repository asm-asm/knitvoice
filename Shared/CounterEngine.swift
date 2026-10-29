import Foundation

/// カウント方法。
enum CountMode: String, Codable, CaseIterable, Identifiable {
    /// 段のみ
    case simple
    /// セット・回・段の3階層
    case set

    var id: String { rawValue }

    var label: String {
        switch self {
        case .simple: return "段のみ"
        case .set: return "セット・回・段"
        }
    }
}

/// プロジェクトの数え方の設定。カウント値（completedRows）は含まない。
struct CounterConfig: Equatable, Codable {
    var mode: CountMode
    /// a：1回あたりの段数
    var rowsPerRepeat: Int
    /// b：1セットあたりの回数
    var repeatsPerSet: Int
    /// 目標セット数（setモード、nilなら無制限）
    var targetSets: Int?
    /// 目標段数（simpleモード、nilなら無制限）
    var targetRows: Int?

    init(
        mode: CountMode = .simple,
        rowsPerRepeat: Int = 2,
        repeatsPerSet: Int = 3,
        targetSets: Int? = nil,
        targetRows: Int? = nil
    ) {
        self.mode = mode
        self.rowsPerRepeat = rowsPerRepeat
        self.repeatsPerSet = repeatsPerSet
        self.targetSets = targetSets
        self.targetRows = targetRows
    }

    /// 0以下が入っていても計算が壊れないようにした a
    var safeRowsPerRepeat: Int { max(1, rowsPerRepeat) }
    /// 0以下が入っていても計算が壊れないようにした b
    var safeRepeatsPerSet: Int { max(1, repeatsPerSet) }
    /// s = a × b
    var rowsPerSet: Int { safeRowsPerRepeat * safeRepeatsPerSet }

    /// 完了となる通算段数。目標なしなら nil。
    var targetTotalRows: Int? {
        switch mode {
        case .simple:
            guard let targetRows, targetRows > 0 else { return nil }
            return targetRows
        case .set:
            guard let targetSets, targetSets > 0 else { return nil }
            return targetSets * rowsPerSet
        }
    }
}

/// completedRows から計算した「今編んでいる段」の位置。
struct CounterPosition: Equatable {
    /// T：編み終えた段数（通算）
    var completedRows: Int
    var set: Int
    var repeatIndex: Int
    var rowInRepeat: Int

    /// 今編んでいる段（通算、1始まり）= T + 1
    var currentRow: Int { completedRows + 1 }
}

/// +1 で新しい段に入ったときに起きたこと（読み上げの優先順位順）。
enum StepEvent: Equatable {
    /// 目標ちょうどに到達
    case finished
    /// 目標を初めて超えた（一度だけ）
    case overTarget
    /// セットの繰り上がり（○セット目に入った）
    case setStarted(Int)
    /// 回の繰り上がり（○回目に入った）
    case repeatStarted(Int)
    /// それ以外（setモードは回の中の段、simpleモードは通算の段）
    case row(Int)
}

struct IncrementOutcome: Equatable {
    var completedRows: Int
    var event: StepEvent
    /// 新しく入った段に該当するリマインド
    var reminders: [ReminderSpec]
    /// 新しく入った段のメモ
    var memos: [MemoSpec]
}

enum DecrementOutcome: Equatable {
    case moved(completedRows: Int)
    /// T=0 で戻ろうとした
    case atStart
}

/// カウントの純粋なロジック。保存値は completedRows だけで、表示はすべてここから計算する。
enum CounterEngine {
    static func position(completedRows: Int, config: CounterConfig) -> CounterPosition {
        let idx = max(0, completedRows)
        let s = config.rowsPerSet
        let a = config.safeRowsPerRepeat
        return CounterPosition(
            completedRows: idx,
            set: idx / s + 1,
            repeatIndex: (idx % s) / a + 1,
            rowInRepeat: idx % a + 1
        )
    }

    static func isFinished(completedRows: Int, config: CounterConfig) -> Bool {
        guard let target = config.targetTotalRows else { return false }
        return completedRows >= target
    }

    /// +1 して completedRows になったときのイベント。
    static func event(arrivingAt completedRows: Int, config: CounterConfig) -> StepEvent {
        if let target = config.targetTotalRows {
            if completedRows == target { return .finished }
            if completedRows == target + 1 { return .overTarget }
        }
        let p = position(completedRows: completedRows, config: config)
        switch config.mode {
        case .simple:
            return .row(p.currentRow)
        case .set:
            if p.rowInRepeat == 1 && p.repeatIndex == 1 { return .setStarted(p.set) }
            if p.rowInRepeat == 1 { return .repeatStarted(p.repeatIndex) }
            return .row(p.rowInRepeat)
        }
    }

    static func increment(
        completedRows: Int,
        config: CounterConfig,
        reminders: [ReminderSpec] = [],
        memos: [MemoSpec] = []
    ) -> IncrementOutcome {
        let next = max(0, completedRows) + 1
        var outcome = IncrementOutcome(
            completedRows: next,
            event: Self.event(arrivingAt: next, config: config),
            reminders: [],
            memos: []
        )
        // 判定は「今編んでいる段」= T + 1。完了後は通知しない。
        if !isFinished(completedRows: next, config: config) {
            let row = next + 1
            outcome.reminders = reminders.filter { $0.rule.matches(row: row, config: config) }
            outcome.memos = memos.filter { $0.row == row }
        }
        return outcome
    }

    static func decrement(completedRows: Int) -> DecrementOutcome {
        completedRows > 0 ? .moved(completedRows: completedRows - 1) : .atStart
    }

    /// 「○セット目○回目○段目」を通算の段番号（1始まり）に変換する。
    static func absoluteRow(set: Int, repeatIndex: Int, rowInRepeat: Int, config: CounterConfig) -> Int {
        let s = max(1, set)
        let r = min(max(1, repeatIndex), config.safeRepeatsPerSet)
        let w = min(max(1, rowInRepeat), config.safeRowsPerRepeat)
        return (s - 1) * config.rowsPerSet + (r - 1) * config.safeRowsPerRepeat + w
    }
}

/// カウンター画面の表示文字列。
struct CounterDisplay: Equatable {
    var primary: String
    var secondary: String?
    var total: String
    var note: String?

    init(completedRows: Int, config: CounterConfig) {
        let p = CounterEngine.position(completedRows: completedRows, config: config)
        total = "通算 \(p.completedRows)段 完了"
        note = nil

        if let target = config.targetTotalRows, p.completedRows >= target {
            primary = "完成！"
            switch config.mode {
            case .simple: secondary = "\(target)／\(target)段"
            case .set: secondary = "\(config.targetSets ?? 0)／\(config.targetSets ?? 0)セット"
            }
            if p.completedRows > target {
                note = "目標を超えています（＋\(p.completedRows - target)段）"
            }
            return
        }

        switch config.mode {
        case .simple:
            primary = "\(p.currentRow)段目"
            secondary = config.targetTotalRows.map { "目標 \($0)段" }
        case .set:
            if let targetSets = config.targetSets, targetSets > 0 {
                primary = "\(p.set)／\(targetSets)セット"
            } else {
                primary = "\(p.set)セット目"
            }
            secondary = "\(p.repeatIndex)回目　\(p.rowInRepeat)／\(config.safeRowsPerRepeat)段"
        }
    }
}

enum RowLabel {
    /// 通算の段番号を説明する文字列。setモードでは「○セット目○回目○段目」も添える。
    static func describe(row: Int, config: CounterConfig) -> String {
        guard config.mode == .set else { return "通算\(row)段目" }
        let p = CounterEngine.position(completedRows: row - 1, config: config)
        return "通算\(row)段目（\(p.set)セット目 \(p.repeatIndex)回目 \(p.rowInRepeat)段目）"
    }
}
