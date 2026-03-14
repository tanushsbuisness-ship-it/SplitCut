import Foundation
import Observation
import OSLog
import SwiftUI
import GoogleMobileAds

@MainActor
@Observable
final class AdsManager: NSObject {
    private let cutsPerInterstitial = AppConfig.Monetization.cutsPerInterstitial

    var isLoadingAd = false
    var errorMessage: String?

    @ObservationIgnored
    @AppStorage(AppConfig.StorageKeys.completedCutsSinceInterstitial)
    private var completedCutsSinceInterstitial = 0

    @ObservationIgnored
    private var interstitialAd: InterstitialAd?

    @ObservationIgnored
    private var hasStartedSDK = false

    private var interstitialAdUnitID: String {
        #if DEBUG
        // Official Google test interstitial for safe development validation.
        return AppConfig.Monetization.debugInterstitialAdUnitID
        #else
        return AppConfig.Monetization.releaseInterstitialAdUnitID
        #endif
    }

    override init() {
        super.init()
    }

    func prepareIfNeeded() async {
        if !hasStartedSDK {
            hasStartedSDK = true
            await MobileAds.shared.start()
            AppLogger.monetization.info("Google Mobile Ads SDK started.")
        }
    }

    func trackCompletedCutAndPresentAdIfNeeded(adsRemoved: Bool) async {
        guard !adsRemoved else { return }
        await prepareIfNeeded()

        completedCutsSinceInterstitial += 1

        if completedCutsSinceInterstitial < cutsPerInterstitial {
            await loadInterstitialIfNeeded()
            return
        }

        guard let interstitialAd else {
            completedCutsSinceInterstitial = cutsPerInterstitial - 1
            await loadInterstitialIfNeeded()
            return
        }

        interstitialAd.present(from: nil)
        completedCutsSinceInterstitial = 0
    }

    func loadInterstitialIfNeeded() async {
        guard interstitialAd == nil, !isLoadingAd else { return }

        isLoadingAd = true
        defer { isLoadingAd = false }

        do {
            let request = Request()
            let ad = try await InterstitialAd.load(with: interstitialAdUnitID, request: request)
            ad.fullScreenContentDelegate = self
            interstitialAd = ad
            errorMessage = nil
            AppLogger.monetization.info("Interstitial ad loaded.")
        } catch {
            errorMessage = error.localizedDescription
            AppLogger.monetization.error("Interstitial ad failed to load: \(error.localizedDescription)")
        }
    }
}

extension AdsManager: FullScreenContentDelegate {
    func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        interstitialAd = nil
        Task {
            await loadInterstitialIfNeeded()
        }
    }

    func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
        errorMessage = error.localizedDescription
        AppLogger.monetization.error("Interstitial failed to present: \(error.localizedDescription)")
        interstitialAd = nil
        Task {
            await loadInterstitialIfNeeded()
        }
    }
}
