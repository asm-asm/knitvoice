import XCTest
@testable import KnitVoice

final class MiscTests: XCTestCase {
    func testFreeProjectLimit() {
        XCTAssertTrue(EntitlementPolicy.canCreateProject(existingCount: 0, isUnlocked: false))
        XCTAssertFalse(EntitlementPolicy.canCreateProject(existingCount: 1, isUnlocked: false))
        XCTAssertTrue(EntitlementPolicy.canCreateProject(existingCount: 5, isUnlocked: true))
    }

    func testCrownAccumulator() {
        var accumulator = CrownAccumulator(threshold: 1.0)
        XCTAssertEqual(accumulator.feed(0.4), 0)
        XCTAssertEqual(accumulator.feed(0.4), 0)
        XCTAssertEqual(accumulator.feed(0.4), 1)
        XCTAssertEqual(accumulator.feed(0.5), 0)
        // 逆方向に回したら溜めた分は捨てる
        XCTAssertEqual(accumulator.feed(-0.6), 0)
        XCTAssertEqual(accumulator.feed(-0.5), -1)
    }

    func testWatchCommandRoundTrip() throws {
        let command = WatchCommand(projectID: UUID(), action: .increment)
        let data = try XCTUnwrap(SyncCoding.encode(command))
        XCTAssertEqual(SyncCoding.decode(WatchCommand.self, from: data), command)
    }

    func testSnapshotRoundTrip() throws {
        let snapshot = WatchSnapshot(
            projects: [WatchProjectSnapshot(
                id: UUID(),
                name: "セーター",
                completedRows: 11,
                config: CounterConfig(mode: .set, rowsPerRepeat: 2, repeatsPerSet: 3, targetSets: 3),
                reminders: [ReminderSpec(id: UUID(), rule: .everyRows(start: 4, interval: 6, count: 3), text: "増し目", speak: true)],
                memos: [MemoSpec(id: UUID(), row: 12, text: "糸替え")],
                updatedAt: Date(timeIntervalSince1970: 1000)
            )],
            generatedAt: Date(timeIntervalSince1970: 1000)
        )
        let data = try XCTUnwrap(SyncCoding.encode(snapshot))
        XCTAssertEqual(SyncCoding.decode(WatchSnapshot.self, from: data), snapshot)
    }

    func testSilentWavHeader() {
        let data = SilentAudio.wavData(seconds: 1, sampleRate: 8000)
        XCTAssertEqual(data.count, 44 + 16000)
        XCTAssertEqual(String(decoding: data.prefix(4), as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
    }
}
