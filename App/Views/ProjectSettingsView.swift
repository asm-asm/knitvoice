import SwiftUI
import SwiftData

struct ProjectSettingsView: View {
    @Bindable var project: Project
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services
    @State private var confirmingReset = false

    private var sortedReminders: [Reminder] {
        project.reminders.sorted { $0.createdAt < $1.createdAt }
    }

    private var sortedMemos: [RowMemo] {
        project.memos.sorted { $0.row < $1.row }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("名前") {
                    TextField("プロジェクト名", text: $project.name)
                }

                CounterConfigSection(
                    mode: $project.mode,
                    rowsPerRepeat: $project.rowsPerRepeat,
                    repeatsPerSet: $project.repeatsPerSet,
                    targetSets: $project.targetSets,
                    targetRows: $project.targetRows
                )

                Section("リマインド") {
                    ForEach(sortedReminders) { reminder in
                        NavigationLink {
                            ReminderEditView(project: project, reminder: reminder)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Label(reminder.text, systemImage: reminder.speak ? "speaker.wave.2" : "bell")
                                Text(reminder.rule.summary(config: project.config))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        let targets = offsets.map { sortedReminders[$0] }
                        for target in targets { services.context.delete(target) }
                        services.counter.save()
                    }
                    NavigationLink {
                        ReminderEditView(project: project, reminder: nil)
                    } label: {
                        Label("リマインドを追加", systemImage: "plus")
                    }
                }

                Section("段ごとのメモ") {
                    ForEach(sortedMemos) { memo in
                        NavigationLink {
                            MemoEditView(project: project, memo: memo)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(memo.text)
                                Text("\(RowLabel.describe(row: memo.row, config: project.config))・\(memo.timing.label)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        let targets = offsets.map { sortedMemos[$0] }
                        for target in targets { services.context.delete(target) }
                        services.counter.save()
                    }
                    NavigationLink {
                        MemoEditView(project: project, memo: nil)
                    } label: {
                        Label("メモを追加", systemImage: "plus")
                    }
                }

                Section {
                    LabeledContent("現在", value: "通算 \(project.completedRows)段 完了")
                    Button("カウントをリセット", role: .destructive) {
                        confirmingReset = true
                    }
                } footer: {
                    Text("リセットは音声では行えません。")
                }
            }
            .navigationTitle("プロジェクト設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完了") {
                        services.counter.save()
                        dismiss()
                    }
                }
            }
            .confirmationDialog("カウントをリセットしますか？", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("0段に戻す", role: .destructive) {
                    services.counter.reset(projectID: project.id, source: .tap)
                }
            } message: {
                Text("通算\(project.completedRows)段の記録が0に戻ります。履歴は残ります。")
            }
        }
        .onDisappear {
            services.counter.save()
        }
    }
}

struct ReminderEditView: View {
    let project: Project
    let reminder: Reminder?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services

    @State private var text: String
    @State private var speak: Bool
    @State private var kind: ReminderKind
    @State private var row: Int
    @State private var start: Int
    @State private var interval: Int
    @State private var limitCount: Bool
    @State private var count: Int

    init(project: Project, reminder: Reminder?) {
        self.project = project
        self.reminder = reminder
        let current = project.completedRows + 1
        _text = State(initialValue: reminder?.text ?? "")
        _speak = State(initialValue: reminder?.speak ?? true)
        _kind = State(initialValue: reminder?.kind ?? .atRow)
        _row = State(initialValue: reminder?.row ?? current)
        _start = State(initialValue: reminder?.start ?? current)
        _interval = State(initialValue: reminder?.interval ?? 2)
        _limitCount = State(initialValue: reminder?.count != nil)
        _count = State(initialValue: reminder?.count ?? 5)
    }

    var body: some View {
        Form {
            Section("内容") {
                TextField("例：増し目", text: $text)
                Toggle("読み上げる（「次の段は〜です」）", isOn: $speak)
            }

            Section("タイミング") {
                Picker("種類", selection: $kind) {
                    ForEach(ReminderKind.allCases) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                switch kind {
                case .atRow:
                    RowInputView(title: "段", row: $row, config: project.config)
                case .everyRows:
                    RowInputView(title: "開始", row: $start, config: project.config)
                    Stepper("\(interval)段ごと", value: $interval, in: 1...999)
                    Toggle("回数を指定", isOn: $limitCount)
                    if limitCount {
                        Stepper("\(count)回", value: $count, in: 1...999)
                    }
                case .setStart, .repeatStart:
                    if project.mode != .set {
                        Text("セットモードのときだけ通知します")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let reminder {
                Section {
                    Button("このリマインドを削除", role: .destructive) {
                        services.context.delete(reminder)
                        services.counter.save()
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(reminder == nil ? "リマインドを追加" : "リマインドを編集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func save() {
        let target: Reminder
        if let reminder {
            target = reminder
        } else {
            target = Reminder()
            services.context.insert(target)
            target.project = project
        }
        target.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        target.speak = speak
        target.kind = kind
        target.row = max(1, row)
        target.start = max(1, start)
        target.interval = max(1, interval)
        target.count = limitCount ? max(1, count) : nil
        services.counter.save()
        dismiss()
    }
}

struct MemoEditView: View {
    let project: Project
    let memo: RowMemo?

    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services
    @State private var text: String
    @State private var row: Int
    @State private var timing: MemoTiming

    init(project: Project, memo: RowMemo?) {
        self.project = project
        self.memo = memo
        _text = State(initialValue: memo?.text ?? "")
        _row = State(initialValue: memo?.row ?? project.completedRows + 1)
        _timing = State(initialValue: memo?.timing ?? .onEnter)
    }

    var body: some View {
        Form {
            Section("段") {
                RowInputView(title: "段", row: $row, config: project.config)
            }
            Section {
                Picker("知らせるタイミング", selection: $timing) {
                    ForEach(MemoTiming.allCases) { timing in
                        Text(timing.label).tag(timing)
                    }
                }
            } footer: {
                Text("＋1してこの段に入ったとき、またはこの段を編み終えて＋1したときに、表示して読み上げます。")
            }
            Section("メモ") {
                TextField("例：ここで糸替え", text: $text, axis: .vertical)
                    .lineLimit(3...8)
            }
            if let memo {
                Section {
                    Button("このメモを削除", role: .destructive) {
                        services.context.delete(memo)
                        services.counter.save()
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(memo == nil ? "メモを追加" : "メモを編集")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func save() {
        let target: RowMemo
        if let memo {
            target = memo
        } else {
            target = RowMemo(row: row, text: "")
            services.context.insert(target)
            target.project = project
        }
        target.row = max(1, row)
        target.timing = timing
        target.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        services.counter.save()
        dismiss()
    }
}
