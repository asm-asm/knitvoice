import XCTest
@testable import KnitVoice

final class CounterEngineTests: XCTestCase {
    /// a=2, b=3, targetSets=3 → s=6
    private let setConfig = CounterConfig(mode: .set, rowsPerRepeat: 2, repeatsPerSet: 3, targetSets: 3)

    // MARK: - 位置の計算（仕様書のテストケース表）

    func testPositionTable() {
        let cases: [(t: Int, set: Int, rep: Int, row: Int)] = [
            (0, 1, 1, 1),
            (1, 1, 1, 2),
            (2, 1, 2, 1),
            (6, 2, 1, 1),
            (11, 2, 3, 2),
            (12, 3, 1, 1),
        ]
        for c in cases {
            let p = CounterEngine.position(completedRows: c.t, config: setConfig)
            XCTAssertEqual(p.set, c.set, "T=\(c.t) set")
            XCTAssertEqual(p.repeatIndex, c.rep, "T=\(c.t) repeat")
            XCTAssertEqual(p.rowInRepeat, c.row, "T=\(c.t) rowInRep")
            XCTAssertEqual(p.currentRow, c.t + 1)
        }
    }

    func testIncrementAnnouncementTable() {
        let cases: [(t: Int, spoken: String)] = [
            (1, "2段目"),
            (2, "2回目"),
            (6, "2セット目に入りました"),
            (11, "2段目"),
            (12, "3セット目に入りました"),
            (18, "全部終わりました"),
        ]
        for c in cases {
            let outcome = CounterEngine.increment(completedRows: c.t - 1, config: setConfig)
            XCTAssertEqual(outcome.completedRows, c.t)
            XCTAssertEqual(Phrases.increment(outcome, style: .full, speakMemos: false), c.spoken, "T=\(c.t)")
        }
    }

    func testFinishedAndOverTarget() {
        XCTAssertFalse(CounterEngine.isFinished(completedRows: 17, config: setConfig))
        XCTAssertTrue(CounterEngine.isFinished(completedRows: 18, config: setConfig))

        // 完了後の +1 は受け付け、「目標を超えています」は一度だけ
        let over = CounterEngine.increment(completedRows: 18, config: setConfig)
        XCTAssertEqual(over.completedRows, 19)
        XCTAssertEqual(over.event, .overTarget)
        XCTAssertEqual(Phrases.increment(over, style: .full, speakMemos: false), "目標を超えています")

        let further = CounterEngine.increment(completedRows: 19, config: setConfig)
        XCTAssertNotEqual(further.event, .overTarget)
    }

    func testNoTargetNeverFinishes() {
        let config = CounterConfig(mode: .set, rowsPerRepeat: 2, repeatsPerSet: 3, targetSets: nil)
        XCTAssertNil(config.targetTotalRows)
        XCTAssertEqual(CounterEngine.increment(completedRows: 17, config: config).event, .setStarted(4))
    }

    // MARK: - 戻る

    func testUndoAcrossSetBoundary() {
        XCTAssertEqual(CounterEngine.decrement(completedRows: 6), .moved(completedRows: 5))
        let p = CounterEngine.position(completedRows: 5, config: setConfig)
        XCTAssertEqual([p.set, p.repeatIndex, p.rowInRepeat], [1, 3, 2])
        XCTAssertEqual(Phrases.undo(completedRows: 5, config: setConfig), "1セット目、3回目の2段目に戻りました")
    }

    func testUndoAtZero() {
        XCTAssertEqual(CounterEngine.decrement(completedRows: 0), .atStart)
        XCTAssertEqual(Phrases.cannotUndo, "これ以上戻れません")
    }

    // MARK: - simpleモード

    func testSimpleMode() {
        let config = CounterConfig(mode: .simple, targetRows: 20)
        let outcome = CounterEngine.increment(completedRows: 10, config: config)
        XCTAssertEqual(outcome.event, .row(12))
        XCTAssertEqual(Phrases.increment(outcome, style: .full, speakMemos: false), "12段目")
        XCTAssertEqual(Phrases.increment(outcome, style: .numberOnly, speakMemos: false), "12")
        XCTAssertNil(Phrases.increment(outcome, style: .silent, speakMemos: false))

        let display = CounterDisplay(completedRows: 11, config: config)
        XCTAssertEqual(display.primary, "12段目")
        XCTAssertEqual(display.total, "通算 11段 完了")
        XCTAssertEqual(Phrases.undo(completedRows: 11, config: config), "12段目に戻りました")

        XCTAssertEqual(CounterEngine.increment(completedRows: 19, config: config).event, .finished)
    }

    // MARK: - 表示

    func testSetDisplay() {
        let display = CounterDisplay(completedRows: 11, config: setConfig)
        XCTAssertEqual(display.primary, "2／3セット")
        XCTAssertEqual(display.secondary, "3回目　2／2段")
        XCTAssertEqual(display.total, "通算 11段 完了")

        let unlimited = CounterConfig(mode: .set, rowsPerRepeat: 2, repeatsPerSet: 3)
        XCTAssertEqual(CounterDisplay(completedRows: 11, config: unlimited).primary, "2セット目")
    }

    func testFinishedDisplay() {
        let display = CounterDisplay(completedRows: 18, config: setConfig)
        XCTAssertEqual(display.primary, "完成！")
        XCTAssertNil(display.note)
        XCTAssertEqual(CounterDisplay(completedRows: 19, config: setConfig).note, "目標を超えています（＋1段）")
    }

    func testPositionSummaryAndCurrent() {
        XCTAssertEqual(Phrases.positionSummary(completedRows: 11, config: setConfig), "2セット目 3回目 2/2段")
        XCTAssertEqual(Phrases.current(completedRows: 11, config: setConfig), "2セット目、3回目の2段目です。通算11段完了")
    }

    func testAbsoluteRowRoundTrip() {
        for row in 1...40 {
            let p = CounterEngine.position(completedRows: row - 1, config: setConfig)
            XCTAssertEqual(
                CounterEngine.absoluteRow(set: p.set, repeatIndex: p.repeatIndex, rowInRepeat: p.rowInRepeat, config: setConfig),
                row
            )
        }
    }

    func testInvalidConfigDoesNotCrash() {
        let config = CounterConfig(mode: .set, rowsPerRepeat: 0, repeatsPerSet: -1)
        XCTAssertEqual(config.rowsPerSet, 1)
        XCTAssertEqual(CounterEngine.position(completedRows: 5, config: config).set, 6)
    }
}
