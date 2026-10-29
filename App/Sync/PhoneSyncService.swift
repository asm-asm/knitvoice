import Foundation
import WatchConnectivity

/// iPhone側のWatch同期。iPhoneが正のデータを持ち、Watchからはコマンドを受け取る。
@MainActor
final class PhoneSyncService: NSObject, WCSessionDelegate {
    private weak var services: AppServices?
    /// sendMessage 失敗→transferUserInfo の再送で同じコマンドが二度届いても一度だけ適用する
    private var appliedCommandIDs: [UUID] = []
    private let appliedHistoryLimit = 500

    init(services: AppServices) {
        self.services = services
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// 最新状態（プロジェクト一覧＋現在位置）をWatchへ送る。
    func publish() {
        guard WCSession.isSupported(), let services else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let snapshot = WatchSnapshot(
            projects: services.counter.allProjects().map { project in
                WatchProjectSnapshot(
                    id: project.id,
                    name: project.displayName,
                    completedRows: project.completedRows,
                    config: project.config,
                    reminders: project.reminderSpecs,
                    memos: project.memoSpecs,
                    updatedAt: project.updatedAt
                )
            },
            generatedAt: Date()
        )
        guard let data = SyncCoding.encode(snapshot) else { return }
        try? session.updateApplicationContext([SyncKeys.snapshot: data])
    }

    private func apply(_ command: WatchCommand) {
        guard let services, !appliedCommandIDs.contains(command.id) else { return }
        appliedCommandIDs.append(command.id)
        if appliedCommandIDs.count > appliedHistoryLimit {
            appliedCommandIDs.removeFirst(appliedCommandIDs.count - appliedHistoryLimit)
        }
        services.reloadIfChangedExternally()
        switch command.action {
        case .increment:
            services.counter.increment(projectID: command.projectID, source: .watch, now: command.issuedAt)
        case .decrement:
            services.counter.decrement(projectID: command.projectID, source: .watch, now: command.issuedAt)
        }
        // 見つからないプロジェクト宛てでも、最新状態を送ってWatch側を正しくする
        publish()
    }

    // MARK: - WCSessionDelegate

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.publish() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.publish() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(message)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        receive(message)
        replyHandler([:])
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        receive(userInfo)
    }

    nonisolated private func receive(_ payload: [String: Any]) {
        guard let data = payload[SyncKeys.command] as? Data,
              let command = SyncCoding.decode(WatchCommand.self, from: data) else { return }
        Task { @MainActor in self.apply(command) }
    }
}
