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
                AppShellView(
                    authSession: authSession,
                    isGuestMode: isGuestMode,
                    onSignOut: {
                        FirebaseSyncService.shared.clearLocalStore(context: modelContext)
                        authSession.signOut()
                        isGuestMode = false
                        lastHydratedUserId = nil
                    },
                    onAccountDeleted: {
                        isGuestMode = false
                        lastHydratedUserId = nil
                    }
                )
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
    let authSession: AuthSessionViewModel
    let isGuestMode: Bool
    let onSignOut: () -> Void
    let onAccountDeleted: () -> Void

    var body: some View {
        TabView {
            ProjectsView()
                .tabItem { Label("Projects", systemImage: "folder") }

            ScrapBinView()
                .tabItem { Label("Scrap Bin", systemImage: "tray.2") }

            SavedPlansView()
                .tabItem { Label("Plans", systemImage: "bookmark") }

            AccountView(
                authSession: authSession,
                isGuestMode: isGuestMode,
                onSignOut: onSignOut,
                onAccountDeleted: onAccountDeleted
            )
            .tabItem { Label("Account", systemImage: "person.circle") }
        }
    }
}

private struct LoginView: View {
    let authSession: AuthSessionViewModel
    let continueAsGuest: () -> Void
    
    @State private var showingPrivacyPolicy = false
    @State private var showingTermsOfService = false
    @State private var showingAccountDeletion = false

    var body: some View {
        ZStack {
            // Background image
            Image("blueprint-background")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
                .overlay {
                    // Gradient overlay to ensure text readability and blend
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.65),
                            Color.black.opacity(0.45),
                            Color.black.opacity(0.65)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                    .blendMode(.multiply)
                }

            VStack(alignment: .leading, spacing: 20) {
                Spacer()

                VStack(alignment: .leading, spacing: 10) {
                    Text("SplitCut")
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Optimize sheet cuts, reuse matching scrap, and keep your shop inventory in one place.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
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

                    Button {
                        continueAsGuest()
                    } label: {
                        Text("Use without data storage")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .frame(maxWidth: .infinity)
                    }
                    .frame(height: 54)
                    .buttonStyle(.borderless)
                }

                if let errorMessage = authSession.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.85))
                }

                Spacer()

                VStack(spacing: 6) {
                    Text("By logging in, you agree to our")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                    HStack(spacing: 8) {
                        Button("Terms of Service") { showingTermsOfService = true }
                        Text("•").foregroundStyle(.white.opacity(0.45))
                        Button("Privacy Policy") { showingPrivacyPolicy = true }
                        Text("•").foregroundStyle(.white.opacity(0.45))
                        Button("Account Deletion") { showingAccountDeletion = true }
                    }
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.9))
                }
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .opacity(0.9)
            }
            .padding(24)
        }
        .sheet(isPresented: $showingPrivacyPolicy) {
            SafariView(url: URL(string: "https://splitcut.netlify.app/privacy")!)
        }
        .sheet(isPresented: $showingTermsOfService) {
            SafariView(url: URL(string: "https://splitcut.netlify.app/terms")!)
        }
        .sheet(isPresented: $showingAccountDeletion) {
            SafariView(url: URL(string: "https://splitcut.netlify.app/account-deletion")!)
        }
    }

    private var googleButton: some View {
        Button {
            authSession.signInWithGoogle()
        } label: {
            HStack(spacing: 12) {
                // Official Google "G" logo
                Image("google-logo")
                    .resizable()
                    .renderingMode(.original)
                    .frame(width: 20, height: 20)
                Text("Sign in with Google")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.black)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(.black.opacity(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(authSession.isGoogleSigningIn)
        .overlay {
            if authSession.isGoogleSigningIn {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.white.opacity(0.7))
                    .overlay {
                        ProgressView()
                            .tint(.gray)
                    }
                    .frame(height: 54)
            }
        }
    }
}

