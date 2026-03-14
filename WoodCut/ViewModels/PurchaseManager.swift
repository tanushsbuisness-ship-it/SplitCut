import Foundation
import Observation
import OSLog
import StoreKit

@MainActor
@Observable
final class PurchaseManager {
    static let removeAdsProductID = AppConfig.Monetization.removeAdsProductID

    var hasRemovedAds = false
    var isLoadingProducts = false
    var isPurchasing = false
    var errorMessage: String?
    var removeAdsProduct: Product?

    private var updatesTask: Task<Void, Never>?
    private var hasBootstrapped = false

    init() {
        updatesTask = observeTransactionUpdates()
    }

    func bootstrapIfNeeded() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        await refreshEntitlements()
    }

    func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let products = try await Product.products(for: [Self.removeAdsProductID])
            removeAdsProduct = products.first
            if removeAdsProduct == nil {
                errorMessage = "The Remove Ads product is not available yet."
                AppLogger.monetization.warning("Remove Ads product could not be loaded.")
            }
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.monetization.error("StoreKit product load failed: \(error.localizedDescription)")
        }
    }

    func purchaseRemoveAds() async {
        if removeAdsProduct == nil {
            await loadProducts()
        }

        guard let removeAdsProduct else {
            if errorMessage == nil {
                errorMessage = "Could not load the Remove Ads purchase."
            }
            return
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await removeAdsProduct.purchase()
            switch result {
            case let .success(.verified(transaction)):
                await transaction.finish()
                await refreshEntitlements()
                errorMessage = nil
                AppLogger.monetization.info("Remove Ads purchase completed.")
            case .success(.unverified(_, let error)):
                errorMessage = error.localizedDescription
                AppLogger.monetization.error("Remove Ads purchase was unverified: \(error.localizedDescription)")
            case .pending:
                errorMessage = "Purchase is pending approval."
                AppLogger.monetization.info("Remove Ads purchase is pending.")
            case .userCancelled:
                break
            @unknown default:
                errorMessage = "The purchase did not complete."
            }
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.monetization.error("Remove Ads purchase failed: \(error.localizedDescription)")
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            errorMessage = nil
            AppLogger.monetization.info("Restore purchases completed.")
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.monetization.error("Restore purchases failed: \(error.localizedDescription)")
        }
    }

    func refreshEntitlements() async {
        var hasUnlockedAdFree = false

        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result else { continue }
            if transaction.productID == Self.removeAdsProductID,
               transaction.revocationDate == nil {
                hasUnlockedAdFree = true
            }
        }

        hasRemovedAds = hasUnlockedAdFree
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task {
            for await result in Transaction.updates {
                guard case let .verified(transaction) = result else { continue }
                await transaction.finish()
                await refreshEntitlements()
            }
        }
    }
}
