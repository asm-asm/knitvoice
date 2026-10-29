import SwiftUI
import WidgetKit

@main
struct KnitVoiceWidgetBundle: WidgetBundle {
    var body: some Widget {
        ProjectWidget()
        if #available(iOS 18.0, *) {
            IncrementControl()
        }
    }
}

/// ロック画面・コントロールセンターに置ける＋1（iOS 18以降）。
@available(iOS 18.0, *)
struct IncrementControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: WidgetConstants.incrementControlKind) {
            ControlWidgetButton(action: IncrementLastUsedProjectIntent()) {
                Label("段を＋1", systemImage: "plus.circle.fill")
            }
        }
        .displayName("段を＋1")
        .description("最後に使ったプロジェクトを1段進めます。")
    }
}
