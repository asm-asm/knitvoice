import SwiftUI
import SwiftData

/// プロジェクトごとのカウント履歴。日付ごと・新しい順。
struct HistoryView: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @Query private var events: [CountEvent]

    init(project: Project) {
        self.project = project
        let id = project.id
        _events = Query(
            filter: #Predicate<CountEvent> { $0.projectId == id },
            sort: [SortDescriptor(\.timestamp, order: .reverse)]
        )
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(HistoryDay.group(events)) { day in
                    Section {
                        ForEach(day.events) { event in
                            HistoryRow(event: event, config: project.config)
                        }
                    } header: {
                        HStack {
                            Text(day.title)
                            Spacer()
                            Text(day.totalLabel)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .overlay {
                if events.isEmpty {
                    ContentUnavailableView("まだ履歴がありません", systemImage: "clock")
                }
            }
            .navigationTitle("履歴")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}

private struct HistoryRow: View {
    let event: CountEvent
    let config: CounterConfig

    /// 端末の12/24時間設定に関係なく「HH:mm」
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(Self.timeFormatter.string(from: event.timestamp))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(deltaLabel)
                .monospacedDigit()
                .fontWeight(.semibold)
                .foregroundStyle(event.delta > 0 ? Color.primary : Color.orange)
            Text("→ \(Phrases.positionSummary(completedRows: event.resultingRows, config: config))（通算\(event.resultingRows)段）")
                .font(.subheadline)
                .lineLimit(2)
            Spacer(minLength: 4)
            Image(systemName: event.source.systemImage)
                .foregroundStyle(.secondary)
                .accessibilityLabel(event.source.label)
        }
    }

    private var deltaLabel: String {
        if event.kind == .reset { return "リセット" }
        return event.delta > 0 ? "＋\(event.delta)" : "−\(-event.delta)"
    }
}

struct HistoryDay: Identifiable {
    let day: Date
    let events: [CountEvent]
    let title: String
    /// その日の delta の合計（リセットは含めない）
    let total: Int

    var id: Date { day }

    var totalLabel: String {
        total >= 0 ? "+\(total)段" : "\(total)段"
    }

    /// 新しい順に並んだイベントを日ごとにまとめる。
    static func group(_ events: [CountEvent], calendar: Calendar = .current, now: Date = Date()) -> [HistoryDay] {
        var result: [HistoryDay] = []
        var currentDay: Date?
        var bucket: [CountEvent] = []

        func flush() {
            guard let day = currentDay, !bucket.isEmpty else { return }
            result.append(HistoryDay(
                day: day,
                events: bucket,
                title: title(for: day, calendar: calendar, now: now),
                total: bucket.filter { $0.kind == .step }.reduce(0) { $0 + $1.delta }
            ))
        }

        for event in events {
            let day = calendar.startOfDay(for: event.timestamp)
            if day != currentDay {
                flush()
                currentDay = day
                bucket = []
            }
            bucket.append(event)
        }
        flush()
        return result
    }

    static func title(for day: Date, calendar: Calendar, now: Date) -> String {
        if calendar.isDate(day, inSameDayAs: now) { return "今日" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) { return "昨日" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = calendar
        formatter.dateFormat = calendar.isDate(day, equalTo: now, toGranularity: .year) ? "M月d日(E)" : "yyyy年M月d日(E)"
        return formatter.string(from: day)
    }
}
