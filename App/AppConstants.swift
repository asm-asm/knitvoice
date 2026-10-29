import Foundation

enum AppConstants {
    /// 非消耗型「プロジェクト無制限」。App Store Connect の Product ID と合わせる
    static let unlockProductID = "knitvoice.unlock"
    // TODO: 公開前に本物のURLへ差し替える
    static let privacyPolicyURL = URL(string: "https://example.com/knitvoice/privacy")!
    /// ウィジェットからアプリを開くURL（knitvoice://project/<UUID>）
    static let urlScheme = "knitvoice"
}
