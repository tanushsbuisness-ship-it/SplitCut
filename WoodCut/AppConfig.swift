import Foundation

enum AppConfig {
    enum Firebase {
        static let serviceInfoFilename = "GoogleService-Info"
        static let usersCollection = "users"
        static let projectsCollection = "projects"
        static let scrapCollection = "scrap"
    }

    enum Monetization {
        static let removeAdsProductID = value(
            env: "SPLITCUT_REMOVE_ADS_PRODUCT_ID",
            default: "splitcut.remove_ads_forever"
        )

        static let releaseInterstitialAdUnitID = value(
            env: "SPLITCUT_ADMOB_INTERSTITIAL_ID",
            default: "ca-app-pub-6808387225838211/1275532842"
        )

        static let debugInterstitialAdUnitID = "ca-app-pub-3940256099942544/4411468910"
        static let cutsPerInterstitial = Int(value(env: "SPLITCUT_CUTS_PER_AD", default: "3")) ?? 3
    }

    enum StorageKeys {
        static let guestMode = "session.isGuestMode"
        static let completedCutsSinceInterstitial = "ads.completedCutsSinceInterstitial"
    }

    private static func value(env: String, default defaultValue: String) -> String {
        let raw = ProcessInfo.processInfo.environment[env]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty == false) ? raw! : defaultValue
    }
}
