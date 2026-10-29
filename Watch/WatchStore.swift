import Foundation
import WatchConnectivity
import WatchKit

/// Watch側の状態。iPhoneの最新状態をキャッシュし、iPhone不在時も楽観的にカウントする。
/// 再接続時は iPhone から届いた値で上書きする。
@MainActor
@Observable
final class WatchStore: NSObject, WCSessionDelegate {
    private(set) var projects: [WatchProjectSnapshot] = []
    /// リマインド・メモ・完了などの画面表示
    var notice: String?
    private(set) var isPhoneReachable = false

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var pendingBeforeActivation: [[String: Any]] = []
    private static let cacheKey = "watchSnapshotCache"

    /// App Store のスクリーンショット用（起動引数 `-demo`）
    static let isDemo = ProcessInfo.processInfo.arguments.contains("-demo")

    override init() {
        super.init()
        if Self.isDemo {
            projects = Self.demoProjects
            notice = "次の段は増し目"
            return
        }
        if let data = defaults.data(forKey: Self.cacheKey),
           let snapshot = SyncCoding.decode(WatchSnapshot.self, from: data) {
            projects = snapshot.projects
        }
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    private static let demoProjects: [WatchProjectSnapshot] = [
        WatchProjectSnapshot(
            id: UUID(), name: "モヘアのセーター", completedRows: 29,
            config: CounterConfig(mode: .set, rowsPerRepeat: 2, repeatsPerSet: 3, targetSets: 10),
            reminders: [], memos: [], updatedAt: Date()
        ),
        WatchProjectSnapshot(
            id: UUID(), name: "ベビーブランケット", completedRows: 63,
            config: CounterConfig(mode: .simple, targetRows: 120),
            reminders: [], memos: [], updatedAt: Date()
        ),
    ]

    func project(id: UUID) -> WatchProjectSnapshot? {
        projects.first { $0.id == id }
    }

    func increment(projectID: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let project = projects[index]
        let outcome = CounterEngine.increment(
            completedRows: project.completedRows,
            config: project.config,
            reminders: project.reminders,
            memos: project.memos
        )
        projects[index].completedRows = outcome.completedRows
        projects[index].updatedAt = Date()
        persist()

        var lines = outcome.reminders.map { "次の段は\($0.text)" } + outcome.memos.map { "メモ：\($0.text)" }
        switch outcome.event {
        case .finished: lines.insert(Phrases.finished, at: 0)
        case .overTarget: lines.insert(Phrases.overTarget, at: 0)
        default: break
        }
        notice = lines.isEmpty ? nil : lines.joined(separator: "\n")
        WatchHaptics.play(for: outcome.event, hasReminder: !outcome.reminders.isEmpty)
        send(.increment, projectID: projectID)
    }

    func decrement(projectID: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        switch CounterEngine.decrement(completedRows: projects[index].completedRows) {
        case .atStart:
            notice = Phrases.cannotUndo
            WKInterfaceDevice.current().play(.failure)
        case .moved(let rows):
            projects[index].completedRows = rows
            projects[index].updatedAt = Date()
            persist()
            notice = nil
            WKInterfaceDevice.current().play(.directionDown)
            send(.decrement, projectID: projectID)
        }
    }

    // MARK: - 送信

    /// 届くときは sendMessage、届かないときは transferUserInfo でキューに積む
    private func send(_ action: WatchCommand.Action, projectID: UUID) {
        guard let data = SyncCoding.encode(WatchCommand(projectID: projectID, action: action)) else { return }
        let payload: [String: Any] = [SyncKeys.command: data]
        let session = WCSession.default
        guard session.activationState == .activated else {
            pendingBeforeActivation.append(payload)
            return
        }
        Self.deliver(payload, via: session)
    }

    nonisolated private static func deliver(_ payload: [String: Any], via session: WCSession) {
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                // 失敗したらキューで再送（iPhone側はコマンドIDで重複を無視する）
                session.transferUserInfo(payload)
            }
        } else {
            session.transferUserInfo(payload)
        }
    }

    private func flushPending() {
        let session = WCSession.default
        for payload in pendingBeforeActivation {
            Self.deliver(payload, via: session)
        }
        pendingBeforeActivation.removeAll()
    }

    private func apply(_ snapshot: WatchSnapshot) {
        projects = snapshot.projects
        persist()
    }

    private func persist() {
        if let data = SyncCoding.encode(WatchSnapshot(projects: projects, generatedAt: Date())) {
            defaults.set(data, forKey: Self.cacheKey)
        }
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let snapshot = Self.decodeSnapshot(session.receivedApplicationContext)
        let reachable = session.isReachable
        Task { @MainActor in
            self.isPhoneReachable = reachable
            if let snapshot { self.apply(snapshot) }
            self.flushPending()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let snapshot = Self.decodeSnapshot(applicationContext) else { return }
        Task { @MainActor in self.apply(snapshot) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.isPhoneReachable = reachable }
    }

    nonisolated private static func decodeSnapshot(_ context: [String: Any]) -> WatchSnapshot? {
        guard let data = context[SyncKeys.snapshot] as? Data else { return nil }
        return SyncCoding.decode(WatchSnapshot.self, from: data)
    }
}

enum WatchHaptics {
    /// 段・回・セットで別パターン。リマインドがあれば通知パターンを優先
    static func play(for event: StepEvent, hasReminder: Bool) {
        let device = WKInterfaceDevice.current()
        if hasReminder {
            device.play(.notification)
            return
        }
        switch event {
        case .row: device.play(.click)
        case .repeatStarted: device.play(.directionUp)
        case .setStarted, .finished: device.play(.success)
        case .overTarget: device.play(.retry)
        }
    }
}
