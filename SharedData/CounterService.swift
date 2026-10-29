import Foundation
import SwiftData
import WidgetKit

/// カウントを変える処理の唯一の経路。タップ・音声・イヤホン・Watch・ウィジェットすべてここを通る。
/// completedRows の更新と CountEvent の記録を、ひとつの保存（トランザクション）でまとめて行う。
@MainActor
struct CounterService {
    let context: ModelContext
    let writer: StoreWriter
    /// 保存後に呼ばれる（アプリ本体では Watch への送信などに使う）
    var onSaved: (@MainActor () -> Void)?

    init(context: ModelContext, writer: StoreWriter, onSaved: (@MainActor () -> Void)? = nil) {
        self.context = context
        self.writer = writer
        self.onSaved = onSaved
    }

    struct IncrementResult {
        let project: Project
        let outcome: IncrementOutcome
    }

    struct DecrementResult {
        let project: Project
        let outcome: DecrementOutcome
    }

    func project(id: UUID) -> Project? {
        var descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func allProjects() -> [Project] {
        let descriptor = FetchDescriptor<Project>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    /// 現在値を読んで +1 し、履歴と一緒に保存する。
    @discardableResult
    func increment(projectID: UUID, source: CountSource, now: Date = Date()) -> IncrementResult? {
        guard let project = project(id: projectID) else { return nil }
        let outcome = CounterEngine.increment(
            completedRows: project.completedRows,
            config: project.config,
            reminders: project.reminderSpecs,
            memos: project.memoSpecs
        )
        apply(rows: outcome.completedRows, delta: 1, kind: .step, source: source, to: project, now: now)
        return IncrementResult(project: project, outcome: outcome)
    }

    /// 現在値を読んで -1 し、履歴と一緒に保存する。T=0 なら何もしない。
    @discardableResult
    func decrement(projectID: UUID, source: CountSource, now: Date = Date()) -> DecrementResult? {
        guard let project = project(id: projectID) else { return nil }
        let outcome = CounterEngine.decrement(completedRows: project.completedRows)
        if case .moved(let rows) = outcome {
            apply(rows: rows, delta: -1, kind: .step, source: source, to: project, now: now)
        }
        return DecrementResult(project: project, outcome: outcome)
    }

    func reset(projectID: UUID, source: CountSource, now: Date = Date()) {
        guard let project = project(id: projectID), project.completedRows != 0 else { return }
        apply(rows: 0, delta: -project.completedRows, kind: .reset, source: source, to: project, now: now)
    }

    /// プロジェクトと、その CountEvent をまとめて削除する。
    func deleteProject(id: UUID) {
        if let project = project(id: id) {
            context.delete(project)
        }
        try? context.delete(model: CountEvent.self, where: #Predicate { $0.projectId == id })
        if LastUsedProject.id == id { LastUsedProject.id = nil }
        save()
    }

    func latestEvent(projectID: UUID) -> CountEvent? {
        var descriptor = FetchDescriptor<CountEvent>(
            predicate: #Predicate { $0.projectId == projectID },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// 名前・設定・リマインドなどの編集を保存する。
    func save() {
        do {
            try context.save()
        } catch {
            assertionFailure("保存に失敗しました: \(error)")
            return
        }
        StoreChangeMarker.markWrite(by: writer)
        WidgetCenter.shared.reloadAllTimelines()
        onSaved?()
    }

    private func apply(rows: Int, delta: Int, kind: CountEventKind, source: CountSource, to project: Project, now: Date) {
        project.completedRows = rows
        project.updatedAt = now
        context.insert(CountEvent(
            projectId: project.id,
            delta: delta,
            resultingRows: rows,
            kind: kind,
            source: source,
            timestamp: now
        ))
        LastUsedProject.id = project.id
        save()
    }
}
