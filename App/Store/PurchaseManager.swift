import Foundation
import StoreKit

/// ¥500 買い切り（非消耗型）のアンロック。真実は StoreKit 側で、ローカルはキャッシュ。
@MainActor
@Observable
final class PurchaseManager {
    private(set) var product: Product?
    private(set) var isUnlocked: Bool
    private(set) var isPurchasing = false
    var errorMessage: String?

    @ObservationIgnored private let cacheKey = "unlockCached"
    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    init() {
        isUnlocked = UserDefaults.standard.bool(forKey: cacheKey)
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }
    }

    func load() async {
        do {
            product = try await Product.products(for: [AppConstants.unlockProductID]).first
        } catch {
            errorMessage = "商品情報を読み込めませんでした"
        }
        await refreshEntitlements()
    }

    func refreshEntitlements() async {
        var unlocked = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == AppConstants.unlockProductID,
               transaction.revocationDate == nil {
                unlocked = true
            }
        }
        setUnlocked(unlocked)
    }

    func purchase() async {
        guard let product else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    await refreshEntitlements()
                } else {
                    errorMessage = "購入を確認できませんでした"
                }
            case .pending, .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = "購入できませんでした：\(error.localizedDescription)"
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            errorMessage = "復元できませんでした：\(error.localizedDescription)"
        }
        await refreshEntitlements()
    }

    private func setUnlocked(_ unlocked: Bool) {
        isUnlocked = unlocked
        UserDefaults.standard.set(unlocked, forKey: cacheKey)
    }
}
