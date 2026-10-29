import Foundation
import SwiftData

/// ウィジェット拡張からストアを開く。毎回新しいコンテナを作り、アプリ側の最新の書き込みを確実に読む。
@MainActor
struct WidgetStore {
    let container: ModelContainer
    let counter: CounterService

    init() throws {
        container = try KnitVoiceStore.makeContainer()
        counter = CounterService(context: container.mainContext, writer: .widget)
    }

    /// 指定がなければ「最後に使ったプロジェクト」、それもなければ最近更新したもの。
    func resolveProject(id: UUID?) -> Project? {
        if let id, let project = counter.project(id: id) { return project }
        if let last = LastUsedProject.id, let project = counter.project(id: last) { return project }
        return counter.allProjects().first
    }
}

/// タイムラインに載せる値（SwiftDataのオブジェクトをビューに持ち込まない）。
struct WidgetProjectData {
    let id: UUID
    let name: String
    let completedRows: Int
    let config: CounterConfig
    let lastCountAt: Date?
    let nextReminder: String?

    var display: CounterDisplay { CounterDisplay(completedRows: completedRows, config: config) }
    var summary: String { Phrases.positionSummary(completedRows: completedRows, config: config) }

    /// ロック画面の丸型用の短縮表記（セットモード：「2-3-2」）
    var compactPosition: String {
        let p = CounterEngine.position(completedRows: completedRows, config: config)
        switch config.mode {
        case .simple: return "\(completedRows)"
        case .set: return "\(p.set)-\(p.repeatIndex)-\(p.rowInRepeat)"
        }
    }

    var openURL: URL {
        URL(string: "\(WidgetConstants.urlScheme)://project/\(id.uuidString)")!
    }

    @MainActor
    init(project: Project, store: WidgetStore) {
        id = project.id
        name = project.displayName
        completedRows = project.completedRows
        config = project.config
        lastCountAt = store.counter.latestEvent(projectID: project.id)?.timestamp
        nextReminder = UpcomingReminder.next(
            completedRows: project.completedRows,
            config: project.config,
            reminders: project.reminderSpecs
        ).map { "\($0.row)段目：\($0.reminder.text)" }
    }

    init(id: UUID, name: String, completedRows: Int, config: CounterConfig, lastCountAt: Date?, nextReminder: String?) {
        self.id = id
        self.name = name
        self.completedRows = completedRows
        self.config = config
        self.lastCountAt = lastCountAt
        self.nextReminder = nextReminder
    }

    static let placeholder = WidgetProjectData(
        id: UUID(),
        name: "セーター",
        completedRows: 10,
        config: CounterConfig(mode: .set, rowsPerRepeat: 2, repeatsPerSet: 3, targetSets: 5),
        lastCountAt: Date(),
        nextReminder: "20段目：増し目"
    )
}

enum WidgetConstants {
    /// アプリ本体の AppConstants.urlScheme と合わせる
    static let urlScheme = "knitvoice"
    static let projectWidgetKind = "KnitVoiceProjectWidget"
    static let incrementControlKind = "KnitVoiceIncrementControl"
}
