import SwiftData
import XCTest
@testable import KnitVoice

@MainActor
final class CounterServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var service: CounterService!

    override func setUp() async throws {
        container = try KnitVoiceStore.makeContainer(inMemory: true)
        service = CounterService(context: container.mainContext, writer: .app)
    }

    private func makeProject(_ config: CounterConfig = CounterConfig(mode: .set, rowsPerRepeat: 2, repeatsPerSet: 3, targetSets: 3)) -> Project {
        let project = Project(name: "テスト", config: config)
        container.mainContext.insert(project)
        service.save()
        return project
    }

    private func events(for project: Project) throws -> [CountEvent] {
        let id = project.id
        return try container.mainContext.fetch(FetchDescriptor<CountEvent>(
            predicate: #Predicate { $0.projectId == id },
            sortBy: [SortDescriptor(\.timestamp)]
        ))
    }

    func testIncrementUpdatesRowsAndRecordsEvent() throws {
        let project = makeProject()
        let result = service.increment(projectID: project.id, source: .voice)
        XCTAssertEqual(result?.outcome.completedRows, 1)
        XCTAssertEqual(project.completedRows, 1)

        let recorded = try events(for: project)
        XCTAssertEqual(recorded.count, 1)
        XCTAssertEqual(recorded[0].delta, 1)
        XCTAssertEqual(recorded[0].resultingRows, 1)
        XCTAssertEqual(recorded[0].source, .voice)
        XCTAssertEqual(LastUsedProject.id, project.id)
    }

    func testDecrementRecordsEventButNotAtZero() throws {
        let project = makeProject()
        XCTAssertEqual(service.decrement(projectID: project.id, source: .tap)?.outcome, .atStart)
        XCTAssertTrue(try events(for: project).isEmpty)

        let start = Date(timeIntervalSince1970: 1000)
        service.increment(projectID: project.id, source: .tap, now: start)
        service.decrement(projectID: project.id, source: .watch, now: start.addingTimeInterval(1))
        XCTAssertEqual(project.completedRows, 0)
        let recorded = try events(for: project)
        XCTAssertEqual(recorded.map(\.delta), [1, -1])
        XCTAssertEqual(recorded.map(\.resultingRows), [1, 0])
        XCTAssertEqual(recorded.last?.source, .watch)
    }

    func testReset() throws {
        let project = makeProject()
        for _ in 0..<5 { service.increment(projectID: project.id, source: .tap) }
        service.reset(projectID: project.id, source: .tap)
        XCTAssertEqual(project.completedRows, 0)
        let last = try XCTUnwrap(try events(for: project).last)
        XCTAssertEqual(last.kind, .reset)
        XCTAssertEqual(last.delta, -5)
    }

    func testDeleteProjectRemovesEvents() throws {
        let keep = makeProject()
        let remove = makeProject()
        service.increment(projectID: keep.id, source: .tap)
        service.increment(projectID: remove.id, source: .tap)
        let removedID = remove.id

        service.deleteProject(id: removedID)

        XCTAssertNil(service.project(id: removedID))
        let remaining = try container.mainContext.fetch(FetchDescriptor<CountEvent>())
        XCTAssertEqual(remaining.map(\.projectId), [keep.id])
    }

    func testLatestEvent() {
        let project = makeProject()
        let start = Date(timeIntervalSince1970: 1000)
        service.increment(projectID: project.id, source: .tap, now: start)
        service.increment(projectID: project.id, source: .widget, now: start.addingTimeInterval(60))
        XCTAssertEqual(service.latestEvent(projectID: project.id)?.source, .widget)
    }

    func testHistoryGroupingAndDailyTotal() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 12))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let id = UUID()
        // 新しい順
        let events = [
            CountEvent(projectId: id, delta: 1, resultingRows: 3, kind: .step, source: .tap, timestamp: now),
            CountEvent(projectId: id, delta: -1, resultingRows: 2, kind: .step, source: .tap, timestamp: now.addingTimeInterval(-60)),
            CountEvent(projectId: id, delta: 1, resultingRows: 3, kind: .step, source: .voice, timestamp: now.addingTimeInterval(-120)),
            CountEvent(projectId: id, delta: -10, resultingRows: 0, kind: .reset, source: .tap, timestamp: yesterday),
            CountEvent(projectId: id, delta: 1, resultingRows: 10, kind: .step, source: .tap, timestamp: yesterday.addingTimeInterval(-60)),
        ]
        let days = HistoryDay.group(events, calendar: calendar, now: now)
        XCTAssertEqual(days.map(\.title), ["今日", "昨日"])
        XCTAssertEqual(days.map(\.events.count), [3, 2])
        XCTAssertEqual(days[0].total, 1)
        XCTAssertEqual(days[0].totalLabel, "+1段")
        // リセットは合計に含めない
        XCTAssertEqual(days[1].total, 1)
    }
}
