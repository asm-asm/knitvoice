import SwiftUI
import SwiftData

struct CounterView: View {
    let projectID: UUID
    @Query private var projects: [Project]

    init(projectID: UUID) {
        self.projectID = projectID
        _projects = Query(filter: #Predicate<Project> { $0.id == projectID })
    }

    var body: some View {
        if let project = projects.first {
            CounterScreen(project: project)
        } else {
            ContentUnavailableView("プロジェクトが見つかりません", systemImage: "questionmark.folder")
        }
    }
}

private struct CounterScreen: View {
    let project: Project

    @Environment(AppServices.self) private var services
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @Query private var latestEvents: [CountEvent]

    @State private var model: CounterViewModel?
    @State private var showingProjectSettings = false
    @State private var showingHistory = false
    @State private var showingMemoPrompt = false
    @State private var memoText = ""

    @ScaledMetric(relativeTo: .largeTitle) private var primarySize: CGFloat = 76
    @ScaledMetric(relativeTo: .title) private var secondarySize: CGFloat = 38
    @ScaledMetric(relativeTo: .title) private var micSize: CGFloat = 72

    init(project: Project) {
        self.project = project
        let id = project.id
        var descriptor = FetchDescriptor<CountEvent>(
            predicate: #Predicate { $0.projectId == id },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        _latestEvents = Query(descriptor)
    }

    var body: some View {
        Group {
            if let model {
                content(model)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(project.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingProjectSettings = true
                } label: {
                    Label("プロジェクト設定", systemImage: "slider.horizontal.3")
                }
            }
        }
        // 設定はシートで開く（push だと onDisappear でマイクが止まるため）
        .sheet(isPresented: $showingProjectSettings) {
            ProjectSettingsView(project: project)
        }
        .sheet(isPresented: $showingHistory) {
            HistoryView(project: project)
        }
        .onAppear {
            if model == nil {
                model = CounterViewModel(projectID: project.id, services: services, settings: settings)
            }
            model?.activate()
        }
        .onDisappear {
            model?.deactivate()
        }
        .onChange(of: scenePhase) { _, phase in
            // MVPは前面のみ保証。バックグラウンドではマイクを止める
            if phase == .background { model?.voice.stop() }
        }
    }

    @ViewBuilder
    private func content(_ model: CounterViewModel) -> some View {
        let display = CounterDisplay(completedRows: project.completedRows, config: project.config)
        VStack(spacing: 12) {
            bannerStack(model)

            Button {
                model.increment()
            } label: {
                VStack(spacing: 8) {
                    Text(display.primary)
                        .font(.system(size: primarySize, weight: .heavy, design: .rounded))
                    if let secondary = display.secondary {
                        Text(secondary)
                            .font(.system(size: secondarySize, weight: .bold, design: .rounded))
                    }
                    Text(display.total)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    if let note = display.note {
                        Text(note)
                            .font(.headline)
                            .foregroundStyle(.orange)
                    }
                    Label("タップで＋1", systemImage: "plus.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.tint)
                        .padding(.top, 8)
                }
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.3)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(CounterPadStyle())
            .accessibilityLabel("\(Phrases.current(completedRows: project.completedRows, config: project.config))。タップで1段進めます")

            lastCount

            controls(model)

            heardText(model)
        }
        .padding()
        .alert("この段にメモ", isPresented: $showingMemoPrompt) {
            TextField("例：ここで糸替え", text: $memoText)
            Button("追加") {
                model.addMemo(memoText)
                memoText = ""
            }
            Button("キャンセル", role: .cancel) { memoText = "" }
        } message: {
            Text(RowLabel.describe(row: project.completedRows + 1, config: project.config))
        }
    }

    // MARK: - Parts

    private func bannerStack(_ model: CounterViewModel) -> some View {
        VStack(spacing: 8) {
            ForEach(model.banners) { banner in
                Button {
                    model.dismiss(banner)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: banner.systemImage)
                        Text(banner.text)
                            .font(.title3.bold())
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "xmark")
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.yellow.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityHint("タップで閉じます")
            }
        }
        .animation(.default, value: model.banners)
    }

    /// 「いま押したっけ？」を防ぐための最後のカウント表示。タップで履歴へ
    @ViewBuilder
    private var lastCount: some View {
        Button {
            showingHistory = true
        } label: {
            if let event = latestEvents.first {
                TimelineView(.everyMinute) { context in
                    Label {
                        Text("最後のカウント：\(RelativeTime.string(for: event.timestamp, now: context.date))（\(event.source.label)）")
                    } icon: {
                        Image(systemName: event.source.systemImage)
                    }
                }
            } else {
                Label("履歴", systemImage: "clock")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private func controls(_ model: CounterViewModel) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Button {
                model.decrement()
            } label: {
                Label("−1", systemImage: "arrow.uturn.backward")
                    .font(.headline)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Spacer()

            Button {
                showingMemoPrompt = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.title2)
            }
            .accessibilityLabel("この段にメモ")

            Button {
                settings.speechEnabled.toggle()
            } label: {
                Image(systemName: settings.speechEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                    .font(.title2)
            }
            .accessibilityLabel(settings.speechEnabled ? "読み上げをオフ" : "読み上げをオン")

            Button {
                model.toggleMicrophone()
            } label: {
                Image(systemName: model.voice.isListening ? "mic.fill" : "mic.slash")
                    .font(.system(size: micSize * 0.42, weight: .bold))
                    .symbolEffect(.pulse, isActive: model.voice.isListening)
                    .frame(width: micSize, height: micSize)
                    .foregroundStyle(model.voice.isListening ? Color.white : Color.primary)
                    .background(
                        Circle().fill(model.voice.isListening ? Color.red : Color.secondary.opacity(0.2))
                    )
            }
            .accessibilityLabel(model.voice.isListening ? "マイクをオフ" : "マイクをオン")
        }
    }

    @ViewBuilder
    private func heardText(_ model: CounterViewModel) -> some View {
        switch model.voice.state {
        case .listening:
            Text(model.voice.lastHeard.isEmpty ? "聞いています…「次」「戻る」「今どこ」" : "聞こえた言葉：\(model.voice.lastHeard)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        case .off:
            EmptyView()
        }
    }
}

private struct CounterPadStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 28)
                    .fill(Color.accentColor.opacity(configuration.isPressed ? 0.28 : 0.12))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

enum RelativeTime {
    static func string(for date: Date, now: Date = Date()) -> String {
        if now.timeIntervalSince(date) < 60 { return "たった今" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
