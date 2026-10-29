import AppIntents
import SwiftUI
import WidgetKit

struct ProjectEntry: TimelineEntry {
    let date: Date
    /// nil：プロジェクトがまだない
    let project: WidgetProjectData?
}

struct ProjectTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ProjectEntry {
        ProjectEntry(date: Date(), project: .placeholder)
    }

    func snapshot(for configuration: SelectProjectIntent, in context: Context) async -> ProjectEntry {
        if context.isPreview {
            return ProjectEntry(date: Date(), project: .placeholder)
        }
        return await entry(for: configuration)
    }

    func timeline(for configuration: SelectProjectIntent, in context: Context) async -> Timeline<ProjectEntry> {
        // カウントのたびにアプリ・インテントから reloadAllTimelines するので、定期更新はしない
        Timeline(entries: [await entry(for: configuration)], policy: .never)
    }

    @MainActor
    private func entry(for configuration: SelectProjectIntent) -> ProjectEntry {
        guard let store = try? WidgetStore(),
              let project = store.resolveProject(id: configuration.project?.id) else {
            return ProjectEntry(date: Date(), project: nil)
        }
        return ProjectEntry(date: Date(), project: WidgetProjectData(project: project, store: store))
    }
}

struct ProjectWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: WidgetConstants.projectWidgetKind,
            intent: SelectProjectIntent.self,
            provider: ProjectTimelineProvider()
        ) { entry in
            ProjectWidgetView(entry: entry)
        }
        .configurationDisplayName("段数カウンター")
        .description("現在の位置を表示し、アプリを開かずに＋1できます。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct ProjectWidgetView: View {
    let entry: ProjectEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let project = entry.project {
                switch family {
                case .systemSmall: SmallView(project: project)
                case .systemMedium: MediumView(project: project)
                case .accessoryRectangular: RectangularView(project: project)
                case .accessoryCircular: CircularView(project: project)
                case .accessoryInline: Text(project.summary)
                default: SmallView(project: project)
                }
            } else {
                EmptyProjectView(family: family)
            }
        }
        .widgetURL(entry.project?.openURL)
        .containerBackground(for: .widget) {
            Color(.secondarySystemBackground)
        }
    }
}

// MARK: - Home screen

private struct PositionLines: View {
    let project: WidgetProjectData

    var body: some View {
        let display = project.display
        VStack(alignment: .leading, spacing: 2) {
            Text(display.primary)
                .font(.system(.title2, design: .rounded).weight(.heavy))
            if let secondary = display.secondary {
                Text(secondary)
                    .font(.system(.headline, design: .rounded))
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.5)
    }
}

private struct SmallView: View {
    let project: WidgetProjectData

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(project.name)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .lineLimit(1)
            PositionLines(project: project)
            Spacer(minLength: 0)
            Button(intent: IncrementProjectIntent(projectID: project.id)) {
                Label("＋1", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MediumView: View {
    let project: WidgetProjectData

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                PositionLines(project: project)
                Spacer(minLength: 0)
                if let lastCountAt = project.lastCountAt {
                    (Text("最後のカウント ") + Text(lastCountAt, style: .relative) + Text("前"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let nextReminder = project.nextReminder {
                    Label(nextReminder, systemImage: "bell.fill")
                        .font(.caption2)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 8) {
                Button(intent: IncrementProjectIntent(projectID: project.id)) {
                    Label("＋1", systemImage: "plus")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(intent: DecrementProjectIntent(projectID: project.id)) {
                    Label("−1", systemImage: "minus")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .frame(width: 104)
        }
    }
}

// MARK: - Lock screen
// ロック画面ウィジェットでのボタン操作はOSで挙動が違うため、タップでアプリを開く（widgetURL）

private struct RectangularView: View {
    let project: WidgetProjectData

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(project.name)
                .font(.headline)
                .widgetAccentable()
                .lineLimit(1)
            Text(project.summary)
                .font(.body.monospacedDigit())
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CircularView: View {
    let project: WidgetProjectData

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text(project.compactPosition)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text(project.config.mode == .set ? "セット-回-段" : "段")
                    .font(.system(size: 8))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .padding(4)
        }
    }
}

private struct EmptyProjectView: View {
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryInline, .accessoryCircular:
            Image(systemName: "list.number")
        default:
            VStack(spacing: 6) {
                Image(systemName: "list.number")
                    .font(.title2)
                Text("アプリでプロジェクトを作成してください")
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
