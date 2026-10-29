import SwiftUI

@main
struct KnitVoiceWatchApp: App {
    @State private var store = WatchStore()

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(store)
        }
    }
}

struct WatchRootView: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                if store.projects.isEmpty {
                    ContentUnavailableView(
                        "プロジェクトなし",
                        systemImage: "iphone",
                        description: Text("iPhoneでプロジェクトを作成してください")
                    )
                } else {
                    List(store.projects) { project in
                        NavigationLink(value: project.id) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.name)
                                    .font(.headline)
                                Text(Phrases.positionSummary(completedRows: project.completedRows, config: project.config))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("プロジェクト")
            .navigationDestination(for: UUID.self) { id in
                WatchCounterView(projectID: id)
            }
        }
    }
}

struct WatchCounterView: View {
    /// Digital Crown で1カウントに必要な回転量（要実機調整）
    static let crownStepThreshold = 1.0

    let projectID: UUID
    @Environment(WatchStore.self) private var store
    @State private var crownValue = 0.0
    @State private var accumulator = CrownAccumulator(threshold: WatchCounterView.crownStepThreshold)

    var body: some View {
        if let project = store.project(id: projectID) {
            let display = CounterDisplay(completedRows: project.completedRows, config: project.config)
            VStack(spacing: 6) {
                if let notice = store.notice {
                    Text(notice)
                        .font(.footnote.bold())
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(6)
                        .background(Color.yellow.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                        .onTapGesture { store.notice = nil }
                }

                Button {
                    store.increment(projectID: projectID)
                } label: {
                    VStack(spacing: 2) {
                        Text(display.primary)
                            .font(.system(.title2, design: .rounded).weight(.heavy))
                        if let secondary = display.secondary {
                            Text(secondary)
                                .font(.system(.headline, design: .rounded))
                        }
                        Text(display.total)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("＋1")
                            .font(.title3.bold())
                            .padding(.top, 2)
                    }
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button("−1") {
                    store.decrement(projectID: projectID)
                }
                .controlSize(.mini)
                .buttonStyle(.bordered)
            }
            .focusable()
            .digitalCrownRotation(
                $crownValue,
                from: -1_000_000,
                through: 1_000_000,
                sensitivity: .low,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )
            .onChange(of: crownValue) { oldValue, newValue in
                switch accumulator.feed(newValue - oldValue) {
                case 1: store.increment(projectID: projectID)
                case -1: store.decrement(projectID: projectID)
                default: break
                }
            }
            .navigationTitle(project.name)
        } else {
            Text("プロジェクトが見つかりません")
        }
    }
}
