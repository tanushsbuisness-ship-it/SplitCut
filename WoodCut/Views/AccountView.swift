import SwiftUI
import SwiftData
import FirebaseAuth

struct AccountView: View {
    let authSession: AuthSessionViewModel
    let isGuestMode: Bool
    let onSignOut: () -> Void
    let onAccountDeleted: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(PurchaseManager.self) private var purchaseManager

    @State private var showingDeleteConfirmation = false
    @State private var showingMonetization = false
    @State private var isDeletingAccount = false
    @State private var deleteError: String?

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Profile
                Section {
                    HStack(spacing: 14) {
                        Circle()
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 52, height: 52)
                            .overlay {
                                Text(initials)
                                    .font(.title3.bold())
                                    .foregroundStyle(.tint)
                            }

                        if isGuestMode {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Guest")
                                    .font(.headline)
                                Text("Data is stored locally only")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                if let name = authSession.currentUserDisplayName, !name.isEmpty {
                                    Text(name)
                                        .font(.headline)
                                }
                                if let email = authSession.currentUserEmail {
                                    Text(email)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // MARK: - Subscription
                Section("Subscription") {
                    if purchaseManager.hasRemovedAds {
                        Label("Ad-Free — Thank you!", systemImage: "crown.fill")
                            .foregroundStyle(.yellow)
                    } else {
                        Button {
                            showingMonetization = true
                        } label: {
                            Label("Remove Ads", systemImage: "crown")
                        }
                    }

                    Button("Restore Purchases") {
                        Task { await purchaseManager.restorePurchases() }
                    }
                    .foregroundStyle(.secondary)
                }

                // MARK: - Sign Out
                Section {
                    Button("Sign Out", role: .none, action: onSignOut)
                }

                // MARK: - Danger Zone
                if !isGuestMode {
                    Section {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            if isDeletingAccount {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Deleting Account…")
                                }
                            } else {
                                Text("Delete Account")
                            }
                        }
                        .disabled(isDeletingAccount)

                        if let deleteError {
                            Text(deleteError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    } header: {
                        Text("Danger Zone")
                    } footer: {
                        Text("Permanently removes your account and all associated data from our servers.")
                    }
                }
            }
            .navigationTitle("Account")
            .sheet(isPresented: $showingMonetization) {
                MonetizationView()
            }
            .confirmationDialog(
                "Delete Account?",
                isPresented: $showingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Account and All Data", role: .destructive) {
                    Task { await performDeleteAccount() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete your account and all your projects, scrap, and saved plans. This cannot be undone.")
            }
        }
    }

    // MARK: - Helpers

    private var initials: String {
        if isGuestMode { return "G" }
        let source = authSession.currentUserDisplayName ?? authSession.currentUserEmail ?? "?"
        let parts = source.split(separator: " ")
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        return String(source.prefix(2)).uppercased()
    }

    private func performDeleteAccount() async {
        isDeletingAccount = true
        deleteError = nil

        await FirebaseSyncService.shared.deleteAllUserData()
        FirebaseSyncService.shared.clearLocalStore(context: modelContext)

        do {
            try await authSession.deleteAccount()
            onAccountDeleted()
        } catch let nsError as NSError {
            if nsError.domain == AuthErrorDomain,
               nsError.code == AuthErrorCode.requiresRecentLogin.rawValue {
                deleteError = "For security, please sign out and sign back in before deleting your account."
            } else {
                deleteError = nsError.localizedDescription
            }
        }

        isDeletingAccount = false
    }
}

#Preview {
    AccountView(
        authSession: AuthSessionViewModel(),
        isGuestMode: false,
        onSignOut: {},
        onAccountDeleted: {}
    )
    .environment(PurchaseManager())
}
