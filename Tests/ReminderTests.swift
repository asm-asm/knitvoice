import XCTest
@testable import KnitVoice

final class ReminderTests: XCTestCase {
    private let setConfig = CounterConfig(mode: .set, rowsPerRepeat: 2, repeatsPerSet: 3, targetSets: 3)

    private func spec(_ rule: ReminderRule, _ text: String = "増し目", speak: Bool = true) -> ReminderSpec {
        ReminderSpec(id: UUID(), rule: rule, text: text, speak: speak)
    }

    func testAtRow() {
        XCTAssertTrue(ReminderRule.atRow(5).matches(row: 5, config: setConfig))
        XCTAssertFalse(ReminderRule.atRow(5).matches(row: 6, config: setConfig))
    }

    func testEveryRows() {
        let rule = ReminderRule.everyRows(start: 4, interval: 3, count: 3)
        let hits = (1...20).filter { rule.matches(row: $0, config: setConfig) }
        XCTAssertEqual(hits, [4, 7, 10])

        let unlimited = ReminderRule.everyRows(start: 2, interval: 5, count: nil)
        XCTAssertEqual((1...20).filter { unlimited.matches(row: $0, config: setConfig) }, [2, 7, 12, 17])
    }

    func testSetAndRepeatStart() {
        XCTAssertEqual((1...14).filter { ReminderRule.setStart.matches(row: $0, config: setConfig) }, [1, 7, 13])
        XCTAssertEqual((1...8).filter { ReminderRule.repeatStart.matches(row: $0, config: setConfig) }, [1, 3, 5, 7])
        let simple = CounterConfig(mode: .simple)
        XCTAssertFalse(ReminderRule.setStart.matches(row: 1, config: simple))
    }

    /// 判定は「今編んでいる段」= T + 1
    func testIncrementCollectsRemindersForNewCurrentRow() {
        let reminder = spec(.atRow(4))
        let memo = MemoSpec(id: UUID(), row: 4, text: "ここで糸替え")
        // T: 2 → 3、今編んでいる段は 4
        let outcome = CounterEngine.increment(completedRows: 2, config: setConfig, reminders: [reminder], memos: [memo])
        XCTAssertEqual(outcome.reminders, [reminder])
        XCTAssertEqual(outcome.memos, [memo])
        XCTAssertEqual(
            Phrases.increment(outcome, style: .full, speakMemos: false),
            "2段目。次の段は増し目です"
        )
        XCTAssertEqual(
            Phrases.increment(outcome, style: .full, speakMemos: true),
            "2段目。次の段は増し目です。メモ、ここで糸替え"
        )
    }

    func testSilentReminderIsShownButNotSpoken() {
        let outcome = CounterEngine.increment(completedRows: 2, config: setConfig, reminders: [spec(.atRow(4), speak: false)])
        XCTAssertEqual(outcome.reminders.count, 1)
        XCTAssertEqual(Phrases.increment(outcome, style: .full, speakMemos: false), "2段目")
    }

    func testNoRemindersAfterFinish() {
        let outcome = CounterEngine.increment(completedRows: 17, config: setConfig, reminders: [spec(.atRow(19))])
        XCTAssertEqual(outcome.event, .finished)
        XCTAssertTrue(outcome.reminders.isEmpty)
    }

    func testNextRow() {
        XCTAssertEqual(ReminderRule.atRow(20).nextRow(from: 12, config: setConfig), 20)
        XCTAssertNil(ReminderRule.atRow(5).nextRow(from: 12, config: setConfig))
        XCTAssertEqual(ReminderRule.everyRows(start: 4, interval: 3, count: 3).nextRow(from: 5, config: setConfig), 7)
        XCTAssertNil(ReminderRule.everyRows(start: 4, interval: 3, count: 3).nextRow(from: 11, config: setConfig))
        XCTAssertEqual(ReminderRule.everyRows(start: 4, interval: 3, count: nil).nextRow(from: 1, config: setConfig), 4)
        XCTAssertEqual(ReminderRule.setStart.nextRow(from: 8, config: setConfig), 13)
        XCTAssertEqual(ReminderRule.setStart.nextRow(from: 7, config: setConfig), 7)
        XCTAssertEqual(ReminderRule.repeatStart.nextRow(from: 4, config: setConfig), 5)
    }

    func testUpcomingReminder() {
        let a = spec(.atRow(15), "減らし目")
        let b = spec(.atRow(20), "増し目")
        let next = UpcomingReminder.next(completedRows: 11, config: setConfig, reminders: [b, a])
        XCTAssertEqual(next?.row, 15)
        XCTAssertEqual(next?.reminder.text, "減らし目")
        // 目標（18段）より後は出さない
        XCTAssertNil(UpcomingReminder.next(completedRows: 11, config: setConfig, reminders: [b]))
    }

    func testRuleCodableRoundTrip() throws {
        let rules: [ReminderRule] = [.atRow(3), .everyRows(start: 2, interval: 4, count: nil), .setStart, .repeatStart]
        let data = try JSONEncoder().encode(rules)
        XCTAssertEqual(try JSONDecoder().decode([ReminderRule].self, from: data), rules)
    }
}
