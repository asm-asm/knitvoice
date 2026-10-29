import AppIntents
import Foundation
import WidgetKit

struct ProjectEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "プロジェクト"
    static var defaultQuery = ProjectEntityQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct ProjectEntityQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [ProjectEntity] {
        try WidgetStore().counter.allProjects()
            .filter { identifiers.contains($0.id) }
            .map { ProjectEntity(id: $0.id, name: $0.displayName) }
    }

    @MainActor
    func suggestedEntities() async throws -> [ProjectEntity] {
        try WidgetStore().counter.allProjects()
            .map { ProjectEntity(id: $0.id, name: $0.displayName) }
    }
}

/// ウィジェットの編集で対象プロジェクトを選ぶ。未選択なら「最後に使ったプロジェクト」。
struct SelectProjectIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "プロジェクトを選択"
    static var description = IntentDescription("ウィジェットに表示するプロジェクトを選びます。未選択なら最後に使ったプロジェクトを表示します。")

    @Parameter(title: "プロジェクト")
    var project: ProjectEntity?
}

/// ウィジェットの＋1。アプリを開かず、読み上げもしない。
struct IncrementProjectIntent: AppIntent {
    static var title: LocalizedStringResource = "段を＋1"
    static var isDiscoverable: Bool = false

    @Parameter(title: "プロジェクトID")
    var projectID: String

    init() {}

    init(projectID: UUID) {
        self.projectID = projectID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: projectID) else { return .result() }
        try WidgetStore().counter.increment(projectID: id, source: .widget)
        return .result()
    }
}

/// ウィジェットの−1。
struct DecrementProjectIntent: AppIntent {
    static var title: LocalizedStringResource = "段を−1"
    static var isDiscoverable: Bool = false

    @Parameter(title: "プロジェクトID")
    var projectID: String

    init() {}

    init(projectID: UUID) {
        self.projectID = projectID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: projectID) else { return .result() }
        try WidgetStore().counter.decrement(projectID: id, source: .widget)
        return .result()
    }
}

/// コントロール（iOS 18）用：最後に使ったプロジェクトを＋1。
struct IncrementLastUsedProjectIntent: AppIntent {
    static var title: LocalizedStringResource = "最後に使ったプロジェクトを＋1"
    static var description = IntentDescription("最後に使ったプロジェクトを1段進めます。")

    @MainActor
    func perform() async throws -> some IntentResult {
        let store = try WidgetStore()
        if let project = store.resolveProject(id: nil) {
            store.counter.increment(projectID: project.id, source: .widget)
        }
        return .result()
    }
}
