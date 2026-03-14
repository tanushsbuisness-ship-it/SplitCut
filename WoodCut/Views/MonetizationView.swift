import SwiftUI
import StoreKit

struct MonetizationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(PurchaseManager.self) private var purchaseManager

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Go Ad-Free")
                        .font(.largeTitle.bold())
                    Text("Interstitial ads appear after every third completed cut plan for free users.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label("One-time purchase", systemImage: "checkmark.circle")
                    Label("Removes ads forever", systemImage: "checkmark.circle")
                    Label("Works with Apple restore purchases", systemImage: "checkmark.circle")
                }
                .font(.subheadline)

                if purchaseManager.hasRemovedAds {
                    Label("Ads are already removed for this Apple account.", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                } else {
                    Button {
                        Task {
                            await purchaseManager.purchaseRemoveAds()
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if purchaseManager.isPurchasing {
                                ProgressView()
                            } else {
                                Text(purchaseTitle)
                                    .font(.headline)
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(purchaseManager.isPurchasing || purchaseManager.isLoadingProducts)
                }

                Button("Restore Purchases") {
                    Task {
                        await purchaseManager.restorePurchases()
                    }
                }
                .disabled(purchaseManager.isPurchasing)

                if let errorMessage = purchaseManager.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .padding(24)
            .navigationTitle("Remove Ads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var purchaseTitle: String {
        if let removeAdsProduct = purchaseManager.removeAdsProduct {
            return "Remove Ads \(removeAdsProduct.displayPrice)"
        }

        return "Remove Ads $4.99"
    }
}

#Preview {
    MonetizationView()
        .environment(PurchaseManager())
}
