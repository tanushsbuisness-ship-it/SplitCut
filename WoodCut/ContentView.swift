//
//  ContentView.swift
//  WoodCut
//
//  Created by Tanush Shrivastava on 3/14/26.
//

import SwiftUI
import SwiftData
import AuthenticationServices
import GoogleSignInSwift

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PurchaseManager.self) private var purchaseManager
    @Environment(AdsManager.self) private var adsManager
    @AppStorage(AppConfig.StorageKeys.guestMode) private var isGuestMode = false
    @State private var authSession = AuthSessionViewModel()
    @State private var lastHydratedUserId: String?

    var body: some View {
        Group {
            if authSession.isAuthenticated || isGuestMode {
                AppShellView {
                    FirebaseSyncService.shared.clearLocalStore(context: modelContext)
                    authSession.signOut()
                    isGuestMode = false
                    lastHydratedUserId = nil
                }
            } else {
                LoginView(
                    authSession: authSession,
                    continueAsGuest: { isGuestMode = true }
                )
            }
        }
        .task(id: authSession.isAuthenticated ? authSession.currentUserId : "signed-out") {
            if authSession.isAuthenticated,
               !isGuestMode,
               let currentUserId = authSession.currentUserId,
               currentUserId != lastHydratedUserId {
                await FirebaseSyncService.shared.hydrateLocalStore(context: modelContext)
                lastHydratedUserId = currentUserId
            } else if !authSession.isAuthenticated && !isGuestMode {
                lastHydratedUserId = nil
            }
        }
        .task {
            await purchaseManager.bootstrapIfNeeded()
            await adsManager.prepareIfNeeded()
        }
        .task(id: authSession.currentUserId) {
            if authSession.currentUserId != nil {
                isGuestMode = false
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(SampleData.previewContainer)
}

private struct AppShellView: View {
    let signOut: () -> Void

    var body: some View {
        TabView {
            ProjectsView(onSignOut: signOut)
                .tabItem { Label("Projects", systemImage: "folder") }

            ScrapBinView()
                .tabItem { Label("Scrap Bin", systemImage: "tray.2") }
        }
    }
}

private struct LoginView: View {
    let authSession: AuthSessionViewModel
    let continueAsGuest: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.92, blue: 0.84),
                    Color(red: 0.81, green: 0.67, blue: 0.46),
                    Color(red: 0.35, green: 0.25, blue: 0.17),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                Spacer()

                VStack(alignment: .leading, spacing: 10) {
                    Text("SplitCut")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("Optimize sheet cuts, reuse matching scrap, and keep your shop inventory in one place.")
                        .font(.subheadline)
                        .foregroundStyle(.black.opacity(0.72))
                }

                VStack(spacing: 12) {
                    SignInWithAppleButton(
                        .continue,
                        onRequest: authSession.prepareAppleRequest,
                        onCompletion: authSession.handleAppleCompletion
                    )
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .overlay {
                        if authSession.isAppleSigningIn {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(.black.opacity(0.18))
                                .overlay {
                                    ProgressView()
                                        .tint(.white)
                                }
                        }
                    }
                    .disabled(authSession.isAppleSigningIn)

                    googleButton

                    Button("Use without data storage") {
                        continueAsGuest()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.black.opacity(0.84))
                }

                if let errorMessage = authSession.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.85))
                }

                Spacer()
            }
            .padding(24)
        }
    }

    private var googleButton: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.white)
                .overlay {
                    GoogleSignInButton(scheme: .light, style: .wide, state: .normal) {
                        authSession.signInWithGoogle()
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                .frame(height: 54)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(.black.opacity(0.08), lineWidth: 0.5)
                }
                .disabled(authSession.isGoogleSigningIn)

            if authSession.isGoogleSigningIn {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(0.5))
                    .overlay {
                        ProgressView()
                    }
                    .frame(height: 54)
            }
        }
    }
}
