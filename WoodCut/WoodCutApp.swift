//
//  WoodCutApp.swift
//  WoodCut
//
//  Created by Tanush Shrivastava on 3/14/26.
//

import SwiftUI
import SwiftData
import FirebaseCore
import OSLog
import UIKit
import GoogleSignIn

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if FirebaseApp.app() == nil,
           Bundle.main.path(forResource: AppConfig.Firebase.serviceInfoFilename, ofType: "plist") != nil {
            FirebaseApp.configure()
        } else if Bundle.main.path(forResource: AppConfig.Firebase.serviceInfoFilename, ofType: "plist") == nil {
            AppLogger.app.warning("Firebase config plist is missing. Cloud features are disabled until it is added to the target.")
        }
        return true
    }
}

@main
struct WoodCutApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var purchaseManager = PurchaseManager()
    @State private var adsManager = AdsManager()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Project.self,
            MaterialItem.self,
            RequiredPiece.self,
            ScrapItem.self,
        ])

        do {
            return try makeContainer(schema: schema, inMemory: false)
        } catch {
            AppLogger.app.error("SwiftData persistent store failed to load: \(String(describing: error))")
            do {
                try removeDefaultSwiftDataStoreFiles()
                AppLogger.app.warning("Removed local SwiftData store files and retrying persistent container creation.")
                return try makeContainer(schema: schema, inMemory: false)
            } catch {
                AppLogger.app.error("SwiftData store reset failed: \(String(describing: error))")
                do {
                    return try makeContainer(schema: schema, inMemory: true)
                } catch {
                    fatalError("Could not create ModelContainer after recovery attempts: \(error)")
                }
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(purchaseManager)
                .environment(adsManager)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}

private func makeContainer(schema: Schema, inMemory: Bool) throws -> ModelContainer {
    let configuration = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: inMemory
    )
    return try ModelContainer(for: schema, configurations: [configuration])
}

private func removeDefaultSwiftDataStoreFiles() throws {
    let fileManager = FileManager.default
    let appSupportURL = try fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )

    let candidateNames = [
        "default.store",
        "default.store-shm",
        "default.store-wal",
        "default.sqlite",
        "default.sqlite-shm",
        "default.sqlite-wal",
    ]

    for name in candidateNames {
        let url = appSupportURL.appendingPathComponent(name)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
}
