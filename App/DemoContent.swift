import Foundation
import SwiftData

/// App Store のスクリーンショット用。起動引数 `-demo` で、メモリ上のストアに見本データを入れて起動する。
/// `-demoScreen list|counter|history|projectSettings` で最初に開く画面を選ぶ。
enum DemoMode {
    private static let arguments = ProcessInfo.processInfo.arguments

    static let isEnabled = arguments.contains("-demo")

    static var screen: String? {
        guard let index = arguments.firstIndex(of: "-demoScreen"), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    /// 見本で最初に開くプロジェクト
    static let mainProjectID = UUID(uuidString: "6B0C1F4E-6A2B-4E0D-9C2B-1F4D2E6A7B10")!

    @MainActor
    static func seed(_ context: ModelContext, now: Date = Date()) {
        let calendar = Calendar.current

        let sweater = Project(name: "モヘアのセーター（前身頃）", config: CounterConfig(
            mode: .set, rowsPerRepeat: 2, repeatsPerSet: 3, targetSets: 10
        ))
        sweater.id = mainProjectID
        context.insert(sweater)

        let increase = Reminder()
        increase.kind = .everyRows
        increase.start = 31
        increase.interval = 6
        increase.count = 5
        increase.text = "増し目"
        context.insert(increase)
        increase.project = sweater

        let pattern = Reminder()
        pattern.kind = .atRow
        pattern.row = 43
        pattern.text = "ここから模様B"
        pattern.createdAt = now.addingTimeInterval(1)
        context.insert(pattern)
        pattern.project = sweater

        let memo = RowMemo(row: 37, text: "糸替え（2玉目）", timing: .onEnter)
        context.insert(memo)
        memo.project = sweater

        // 履歴：昨日 1〜17段、今日 18〜29段（途中で1回戻る）→ 通算29段（5セット目 3回目 2/2段）
        var rows = 0
        func record(_ delta: Int, _ source: CountSource, _ date: Date) {
            rows += delta
            context.insert(CountEvent(projectId: sweater.id, delta: delta, resultingRows: rows, kind: .step, source: source, timestamp: date))
        }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.date(bySettingHour: 20, minute: 10, second: 0, of: now)!)!
        for i in 0..<17 {
            record(1, i % 3 == 0 ? .tap : .voice, yesterday.addingTimeInterval(Double(i) * 150))
        }
        let todaySources: [CountSource] = [.voice, .voice, .watch, .voice, .earphone, .voice, .widget, .voice, .voice, .watch, .voice, .voice]
        for (i, source) in todaySources.enumerated() {
            record(1, source, now.addingTimeInterval(Double(i - todaySources.count) * 170 - 180))
            if i == 7 {
                record(-1, .voice, now.addingTimeInterval(Double(i - todaySources.count) * 170 - 120))
                record(1, .voice, now.addingTimeInterval(Double(i - todaySources.count) * 170 - 100))
            }
        }
        sweater.completedRows = rows
        sweater.updatedAt = now.addingTimeInterval(-180)

        let blanket = Project(name: "ベビーブランケット", config: CounterConfig(mode: .simple, targetRows: 120))
        blanket.completedRows = 63
        blanket.updatedAt = calendar.date(byAdding: .day, value: -2, to: now)!
        context.insert(blanket)

        let bag = Project(name: "かぎ針のミニバッグ", config: CounterConfig(mode: .set, rowsPerRepeat: 4, repeatsPerSet: 2, targetSets: 6))
        bag.completedRows = 13
        bag.updatedAt = calendar.date(byAdding: .day, value: -5, to: now)!
        context.insert(bag)

        try? context.save()
        LastUsedProject.id = sweater.id
    }
}
