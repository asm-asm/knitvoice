import SwiftUI
import SwiftData

struct ProjectListView: View {
    @Environment(AppServices.self) private var services
    @Environment(PurchaseManager.self) private var purchases
    @Query(sort: \Project.updatedAt, order: .reverse) private var projects: [Project]

    @State private var showingNewProject = false
    @State private var showingPaywall = false
    @State private var showingSettings = false
    @State private var projectToDelete: Project?

    var body: some View {
        List {
            ForEach(projects) { project in
                NavigationLink(value: project.id) {
                    ProjectRow(project: project)
                }
                .swipeActions {
                    Button(role: .destructive) {
                        projectToDelete = project
                    } label: {
                        Label("削除", systemImage: "trash")
                    }
                }
            }
        }
        .overlay {
            if projects.isEmpty {
                ContentUnavailableView {
                    Label("プロジェクトがありません", systemImage: "list.number")
                } description: {
                    Text("作品ごとにプロジェクトを作って段数を数えます")
                } actions: {
                    Button("プロジェクトを作成") { addTapped() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("プロジェクト")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingSettings = true
                } label: {
                    Label("設定", systemImage: "gearshape")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    addTapped()
                } label: {
                    Label("追加", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewProject) { NewProjectView() }
        .sheet(isPresented: $showingPaywall) { PaywallView() }
        .sheet(isPresented: $showingSettings) { AppSettingsView() }
        .confirmationDialog(
            "プロジェクトを削除しますか？",
            isPresented: Binding(
                get: { projectToDelete != nil },
                set: { if !$0 { projectToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: projectToDelete
        ) { project in
            Button("「\(project.displayName)」を削除", role: .destructive) {
                services.counter.deleteProject(id: project.id)
            }
        } message: { _ in
            Text("カウント・リマインド・メモ・履歴がすべて消えます。元に戻せません。")
        }
    }

    private func addTapped() {
        if EntitlementPolicy.canCreateProject(existingCount: projects.count, isUnlocked: purchases.isUnlocked) {
            showingNewProject = true
        } else {
            showingPaywall = true
        }
    }
}

private struct ProjectRow: View {
    let project: Project

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.displayName)
                .font(.headline)
            Text(project.positionSummary)
                .font(.title3.bold())
                .monospacedDigit()
            Text("最終更新 \(project.updatedAt.formatted(.relative(presentation: .named)))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct NewProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppServices.self) private var services

    @State private var name = ""
    @State private var mode: CountMode = .simple
    @State private var rowsPerRepeat = 2
    @State private var repeatsPerSet = 3
    @State private var targetSets: Int?
    @State private var targetRows: Int?

    var body: some View {
        NavigationStack {
            Form {
                Section("名前") {
                    TextField("例：モヘアのセーター", text: $name)
                }
                CounterConfigSection(
                    mode: $mode,
                    rowsPerRepeat: $rowsPerRepeat,
                    repeatsPerSet: $repeatsPerSet,
                    targetSets: $targetSets,
                    targetRows: $targetRows
                )
            }
            .navigationTitle("新しいプロジェクト")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("作成") { create() }
                }
            }
        }
    }

    private func create() {
        let config = CounterConfig(
            mode: mode,
            rowsPerRepeat: rowsPerRepeat,
            repeatsPerSet: repeatsPerSet,
            targetSets: targetSets,
            targetRows: targetRows
        )
        let project = Project(name: name.trimmingCharacters(in: .whitespacesAndNewlines), config: config)
        services.context.insert(project)
        LastUsedProject.id = project.id
        services.counter.save()
        dismiss()
    }
}
