import Foundation

enum ReminderKind: String, Codable, CaseIterable, Identifiable {
    case atRow
    case everyRows
    case setStart
    case repeatStart

    var id: String { rawValue }

    var label: String {
        switch self {
        case .atRow: return "指定の段"
        case .everyRows: return "一定間隔"
        case .setStart: return "各セットの1段目"
        case .repeatStart: return "各回の1段目"
        }
    }
}

/// リマインドの判定規則。段番号はすべて通算（1始まり）。
enum ReminderRule: Equatable, Codable {
    /// 通算n段目
    case atRow(Int)
    /// start段目から interval段ごとに count回（nilなら無制限）
    case everyRows(start: Int, interval: Int, count: Int?)
    /// 各セットの1段目
    case setStart
    /// 各回の1段目
    case repeatStart

    var kind: ReminderKind {
        switch self {
        case .atRow: return .atRow
        case .everyRows: return .everyRows
        case .setStart: return .setStart
        case .repeatStart: return .repeatStart
        }
    }

    /// 「今編んでいる段」row に該当するか。
    func matches(row: Int, config: CounterConfig) -> Bool {
        guard row >= 1 else { return false }
        switch self {
        case .atRow(let n):
            return row == n
        case let .everyRows(start, interval, count):
            let step = max(1, interval)
            guard row >= start else { return false }
            let offset = row - start
            guard offset % step == 0 else { return false }
            if let count { return offset / step < count }
            return true
        case .setStart:
            return config.mode == .set && (row - 1) % config.rowsPerSet == 0
        case .repeatStart:
            return config.mode == .set && (row - 1) % config.safeRowsPerRepeat == 0
        }
    }

    /// row 以降で最初に該当する段（通算）。なければ nil。
    func nextRow(from row: Int, config: CounterConfig) -> Int? {
        let from = max(1, row)
        switch self {
        case .atRow(let n):
            return n >= from ? n : nil
        case let .everyRows(start, interval, count):
            let step = max(1, interval)
            let k = from <= start ? 0 : (from - start + step - 1) / step
            if let count, k >= count { return nil }
            return start + k * step
        case .setStart:
            guard config.mode == .set else { return nil }
            return Self.nextMultipleRow(from: from, period: config.rowsPerSet)
        case .repeatStart:
            guard config.mode == .set else { return nil }
            return Self.nextMultipleRow(from: from, period: config.safeRowsPerRepeat)
        }
    }

    /// (row - 1) が period の倍数になる最小の row（row >= from）
    private static func nextMultipleRow(from: Int, period: Int) -> Int {
        ((from - 1 + period - 1) / period) * period + 1
    }

    func summary(config: CounterConfig) -> String {
        switch self {
        case .atRow(let n):
            return RowLabel.describe(row: n, config: config)
        case let .everyRows(start, interval, count):
            let times = count.map { "・\($0)回" } ?? "・ずっと"
            return "\(start)段目から\(max(1, interval))段ごと\(times)"
        case .setStart:
            return "各セットの1段目"
        case .repeatStart:
            return "各回の1段目"
        }
    }
}

/// 永続化層から切り離したリマインド（ロジック・Watch同期用）。
struct ReminderSpec: Equatable, Codable, Identifiable {
    var id: UUID
    var rule: ReminderRule
    var text: String
    var speak: Bool
}

enum UpcomingReminder {
    /// 「今編んでいる段」以降で最初のリマインド（同じ段なら登録順で先のもの）。完了後・目標超えは nil。
    static func next(
        completedRows: Int,
        config: CounterConfig,
        reminders: [ReminderSpec]
    ) -> (row: Int, reminder: ReminderSpec)? {
        let current = max(0, completedRows) + 1
        var best: (row: Int, reminder: ReminderSpec)?
        for reminder in reminders {
            guard let row = reminder.rule.nextRow(from: current, config: config) else { continue }
            if let target = config.targetTotalRows, row > target { continue }
            if best == nil || row < best!.row { best = (row, reminder) }
        }
        return best
    }
}

/// 永続化層から切り離した段ごとのメモ。
struct MemoSpec: Equatable, Codable, Identifiable {
    var id: UUID
    /// 通算の段番号（1始まり）
    var row: Int
    var text: String
}
