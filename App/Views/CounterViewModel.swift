import SwiftUI
import UIKit

@MainActor
@Observable
final class CounterViewModel {
    struct Banner: Identifiable, Equatable {
        let id = UUID()
        let systemImage: String
        let text: String
    }

    /// 画面上部のリマインド・メモ（タップで閉じる）
    private(set) var banners: [Banner] = []
    let voice: VoiceController

    @ObservationIgnored let projectID: UUID
    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var isActive = false

    init(projectID: UUID, services: AppServices, settings: AppSettings) {
        self.projectID = projectID
        self.services = services
        self.settings = settings
        self.voice = VoiceController(speaker: services.speaker)
        voice.onCommand = { [weak self] command in self?.handleVoice(command) }
    }

    // MARK: - 画面の表示・非表示

    func activate() {
        guard !isActive else { return }
        isActive = true
        services.counterScreenDidAppear()
        LastUsedProject.id = projectID
        AudioSession.configure(allowMixing: !settings.earphoneButtonsEnabled)
        voice.debounceInterval = settings.commandDebounceInterval
        if settings.earphoneButtonsEnabled {
            services.remote.onIncrement = { [weak self] in self?.increment(source: .earphone) }
            services.remote.onDecrement = { [weak self] in self?.decrement(source: .earphone) }
            services.remote.enable(owner: self)
            refreshNowPlaying()
        }
    }

    func deactivate() {
        guard isActive else { return }
        isActive = false
        services.counterScreenDidDisappear()
        voice.stop()
        services.remote.disable(owner: self)
    }

    // MARK: - カウント

    func increment(source: CountSource = .tap) {
        services.reloadIfChangedExternally()
        guard let result = services.counter.increment(projectID: projectID, source: source) else { return }
        let outcome = result.outcome

        var newBanners: [Banner] = []
        switch outcome.event {
        case .finished: newBanners.append(Banner(systemImage: "party.popper", text: Phrases.finished))
        case .overTarget: newBanners.append(Banner(systemImage: "exclamationmark.triangle", text: Phrases.overTarget))
        default: break
        }
        newBanners += outcome.reminders.map { Banner(systemImage: "bell.fill", text: "次の段は\($0.text)") }
        newBanners += outcome.memos.map { Banner(systemImage: "note.text", text: $0.text) }
        banners = newBanners

        if settings.speechEnabled,
           let text = Phrases.increment(outcome, style: settings.rowReadingStyle, speakMemos: settings.speakMemos) {
            services.speaker.speak(text)
        }
        PhoneHaptics.play(for: outcome.event)
        refreshNowPlaying()
    }

    func decrement(source: CountSource = .tap) {
        services.reloadIfChangedExternally()
        guard let result = services.counter.decrement(projectID: projectID, source: source) else { return }
        switch result.outcome {
        case .atStart:
            banners = [Banner(systemImage: "exclamationmark.circle", text: Phrases.cannotUndo)]
            if settings.speechEnabled { services.speaker.speak(Phrases.cannotUndo) }
            PhoneHaptics.blocked()
        case .moved(let rows):
            banners = []
            if settings.speechEnabled {
                services.speaker.speak(Phrases.undo(completedRows: rows, config: result.project.config))
            }
            PhoneHaptics.undo()
        }
        refreshNowPlaying()
    }

    /// 「今どこ」：読み上げOFFでも、聞かれたら答える
    func readPosition() {
        services.reloadIfChangedExternally()
        guard let project = services.counter.project(id: projectID) else { return }
        services.speaker.speak(Phrases.current(completedRows: project.completedRows, config: project.config))
    }

    /// 「この段にメモ」：今編んでいる段に追加し、この段を編み終えて＋1したときに読む
    func addMemo(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let project = services.counter.project(id: projectID) else { return }
        let memo = RowMemo(row: project.completedRows + 1, text: trimmed, timing: .onFinish)
        services.context.insert(memo)
        memo.project = project
        services.counter.save()
        banners = [Banner(systemImage: "note.text", text: "メモを追加：\(trimmed)（この段を編み終えたら知らせます）")]
    }

    /// スクリーンショット用：マイクON・リマインドのバナーを表示した状態
    func showDemoState() {
        banners = [Banner(systemImage: "bell.fill", text: "次の段は増し目")]
        voice.showDemo(heard: "次")
    }

    func dismiss(_ banner: Banner) {
        banners.removeAll { $0.id == banner.id }
    }

    func toggleMicrophone() {
        if voice.isListening {
            voice.stop()
        } else {
            Task { await voice.start() }
        }
    }

    private func handleVoice(_ command: VoiceCommand) {
        switch command {
        case .increment: increment(source: .voice)
        case .decrement: decrement(source: .voice)
        case .readPosition: readPosition()
        }
    }

    private func refreshNowPlaying() {
        guard let project = services.counter.project(id: projectID) else { return }
        services.remote.updateNowPlaying(title: project.displayName, detail: project.positionSummary)
    }
}

enum PhoneHaptics {
    static func play(for event: StepEvent) {
        switch event {
        case .row:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        case .repeatStarted:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .setStarted, .finished:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .overTarget:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    static func undo() {
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    static func blocked() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
