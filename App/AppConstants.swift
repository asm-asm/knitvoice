import Foundation

enum AppConstants {
    /// 非消耗型「プロジェクト無制限」。App Store Connect の Product ID と合わせる
    static let unlockProductID = "knitvoice.unlock"
    static let privacyPolicyURL = URL(string: "https://asm-asm.github.io/knitvoice/privacy.html")!
    static let supportURL = URL(string: "https://asm-asm.github.io/knitvoice/")!
    /// Apple 標準の使用許諾契約（EULA）
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    /// ウィジェットからアプリを開くURL（knitvoice://project/<UUID>）
    static let urlScheme = "knitvoice"
}
