import Foundation
import SwiftData
import UIKit

/// アプリ本体で共有するサービス群とストア。
@MainActor
@Observable
final class AppServices {
    /// ウィジェットが書いたストアを読み直すと差し替わる
    private(set) var container: ModelContainer
    /// 差し替えのたびに増える。ルートの `.id()` に使い、ビュー階層を新しいコンテナで作り直す
    private(set) var storeGeneration = 0

    @ObservationIgnored let speaker = Speaker()
    @ObservationIgnored let remote = RemoteCommandController()
    @ObservationIgnored private(set) var sync: PhoneSyncService!
    @ObservationIgnored private var knownWriteToken: String?

    init() {
        KnitVoiceStore.migrateLegacyStoreIfNeeded()
        do {
            container = try KnitVoiceStore.makeContainer()
        } catch {
            fatalError("ストアを開けませんでした: \(error)")
        }
        knownWriteToken = StoreChangeMarker.currentToken
        sync = PhoneSyncService(services: self)
    }

    var context: ModelContext { container.mainContext }

    /// カウント・編集はすべてこれを通す。
    var counter: CounterService {
        CounterService(context: context, writer: .app) { [weak self] in
            self?.knownWriteToken = StoreChangeMarker.currentToken
            self?.sync.publish()
        }
    }

    /// ウィジェットがストアを書いていたら、コンテナを作り直して最新値を読み込む。
    /// 書き込み前にも呼ぶことで、ウィジェットとの競合で値がずれないようにする。
    @discardableResult
    func reloadIfChangedExternally() -> Bool {
        let token = StoreChangeMarker.currentToken
        guard token != knownWriteToken else { return false }
        do {
            container = try KnitVoiceStore.makeContainer()
            knownWriteToken = token
            storeGeneration += 1
            return true
        } catch {
            return false
        }
    }

    // ストア再読み込みでカウンター画面が作り直されるとき、新旧の表示・非表示の順番が前後しても
    // スリープ防止が外れないよう、表示中の画面数で管理する
    @ObservationIgnored private var visibleCounterScreens = 0

    func counterScreenDidAppear() {
        visibleCounterScreens += 1
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func counterScreenDidDisappear() {
        visibleCounterScreens = max(0, visibleCounterScreens - 1)
        UIApplication.shared.isIdleTimerDisabled = visibleCounterScreens > 0
    }

    /// 前面に戻ったとき：ストアを読み直し、Watchへ最新状態を送る。
    func sceneDidBecomeActive() {
        reloadIfChangedExternally()
        sync.publish()
    }
}
