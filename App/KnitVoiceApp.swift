import SwiftUI
import SwiftData

@main
struct KnitVoiceApp: App {
    @State private var services = AppServices()
    @State private var settings = AppSettings()
    @State private var purchases = PurchaseManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(services)
                .environment(settings)
                .environment(purchases)
                .task { await purchases.load() }
        }
    }
}

struct RootView: View {
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    /// プロジェクトIDで遷移する。ストアを読み直してビュー階層を作り直しても開いている画面を保てる
    @State private var path: [UUID] = DemoMode.isEnabled && (DemoMode.screen ?? "list") != "list"
        ? [DemoMode.mainProjectID]
        : []

    var body: some View {
        NavigationStack(path: $path) {
            ProjectListView()
                .navigationDestination(for: UUID.self) { id in
                    CounterView(projectID: id)
                }
        }
        .modelContainer(services.container)
        .id(services.storeGeneration)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { services.sceneDidBecomeActive() }
        }
        .onOpenURL { url in
            // knitvoice://project/<UUID>（ウィジェットから）
            guard url.scheme == AppConstants.urlScheme, url.host() == "project",
                  let id = UUID(uuidString: url.lastPathComponent) else { return }
            services.reloadIfChangedExternally()
            path = [id]
        }
    }
}
