import Foundation
import SwiftData

@Model
final class Project {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// 編み終えた段数（通算）。これが唯一のカウント値。
    var completedRows: Int = 0
    var modeRaw: String = CountMode.simple.rawValue
    var rowsPerRepeat: Int = 2
    var repeatsPerSet: Int = 3
    var targetSets: Int?
    var targetRows: Int?
    @Relationship(deleteRule: .cascade, inverse: \Reminder.project) var reminders: [Reminder] = []
    @Relationship(deleteRule: .cascade, inverse: \RowMemo.project) var memos: [RowMemo] = []

    init(name: String, config: CounterConfig) {
        self.name = name
        self.modeRaw = config.mode.rawValue
        self.rowsPerRepeat = config.rowsPerRepeat
        self.repeatsPerSet = config.repeatsPerSet
        self.targetSets = config.targetSets
        self.targetRows = config.targetRows
    }

    var mode: CountMode {
        get { CountMode(rawValue: modeRaw) ?? .simple }
        set { modeRaw = newValue.rawValue }
    }

    var config: CounterConfig {
        CounterConfig(
            mode: mode,
            rowsPerRepeat: rowsPerRepeat,
            repeatsPerSet: repeatsPerSet,
            targetSets: targetSets,
            targetRows: targetRows
        )
    }

    var displayName: String { name.isEmpty ? "無題のプロジェクト" : name }

    var reminderSpecs: [ReminderSpec] {
        reminders.sorted { $0.createdAt < $1.createdAt }.map(\.spec)
    }

    var memoSpecs: [MemoSpec] {
        memos.sorted { $0.createdAt < $1.createdAt }.map(\.spec)
    }

    var positionSummary: String {
        Phrases.positionSummary(completedRows: completedRows, config: config)
    }
}

@Model
final class Reminder {
    var id: UUID = UUID()
    var kindRaw: String = ReminderKind.atRow.rawValue
    /// atRow：通算n段目
    var row: Int = 1
    /// everyRows：開始段・間隔・回数（nilなら無制限）
    var start: Int = 1
    var interval: Int = 2
    var count: Int?
    var text: String = ""
    var speak: Bool = true
    var createdAt: Date = Date()
    var project: Project?

    init() {}

    var kind: ReminderKind {
        get { ReminderKind(rawValue: kindRaw) ?? .atRow }
        set { kindRaw = newValue.rawValue }
    }

    var rule: ReminderRule {
        switch kind {
        case .atRow: return .atRow(row)
        case .everyRows: return .everyRows(start: start, interval: interval, count: count)
        case .setStart: return .setStart
        case .repeatStart: return .repeatStart
        }
    }

    var spec: ReminderSpec {
        ReminderSpec(id: id, rule: rule, text: text, speak: speak)
    }
}

@Model
final class RowMemo {
    var id: UUID = UUID()
    /// 通算の段番号（1始まり）
    var row: Int = 1
    var text: String = ""
    var createdAt: Date = Date()
    var project: Project?

    init(row: Int, text: String) {
        self.row = row
        self.text = text
    }

    var spec: MemoSpec { MemoSpec(id: id, row: row, text: text) }
}

/// カウントの入力元。
enum CountSource: String, Codable, CaseIterable {
    case tap
    case voice
    case earphone
    case watch
    case widget

    var label: String {
        switch self {
        case .tap: return "タップ"
        case .voice: return "音声"
        case .earphone: return "イヤホン"
        case .watch: return "Watch"
        case .widget: return "ウィジェット"
        }
    }

    var systemImage: String {
        switch self {
        case .tap: return "hand.tap"
        case .voice: return "mic"
        case .earphone: return "earbuds"
        case .watch: return "applewatch"
        case .widget: return "square.grid.2x2"
        }
    }
}

enum CountEventKind: String, Codable {
    case step
    case reset
}

/// カウント履歴。自動削除しない。
@Model
final class CountEvent {
    var id: UUID = UUID()
    var projectId: UUID = UUID()
    var timestamp: Date = Date()
    /// +1 / -1。リセットのときは変更前の段数のマイナス値。
    var delta: Int = 0
    /// 変更後の completedRows
    var resultingRows: Int = 0
    var kindRaw: String = CountEventKind.step.rawValue
    var sourceRaw: String = CountSource.tap.rawValue

    init(projectId: UUID, delta: Int, resultingRows: Int, kind: CountEventKind, source: CountSource, timestamp: Date = Date()) {
        self.projectId = projectId
        self.delta = delta
        self.resultingRows = resultingRows
        self.kindRaw = kind.rawValue
        self.sourceRaw = source.rawValue
        self.timestamp = timestamp
    }

    var kind: CountEventKind { CountEventKind(rawValue: kindRaw) ?? .step }
    var source: CountSource { CountSource(rawValue: sourceRaw) ?? .tap }
}
