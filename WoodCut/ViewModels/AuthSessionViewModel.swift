import Foundation
import Observation
import OSLog
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import UIKit
import AuthenticationServices
import CryptoKit

@MainActor
@Observable
final class AuthSessionViewModel {
    var isAuthenticated: Bool = false
    var isGoogleSigningIn: Bool = false
    var isAppleSigningIn: Bool = false
    var errorMessage: String?
    var currentUserId: String? = nil

    private var authListener: AuthStateDidChangeListenerHandle?
    private var currentNonce: String?

    init() {
        guard FirebaseApp.app() != nil else {
            errorMessage = "Add \(AppConfig.Firebase.serviceInfoFilename).plist to the Xcode target to enable Firebase sign-in."
            return
        }

        isAuthenticated = Auth.auth().currentUser != nil
        currentUserId = Auth.auth().currentUser?.uid
        authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            Task { @MainActor in
                self.isAuthenticated = user != nil
                self.currentUserId = user?.uid
                if user != nil {
                    self.errorMessage = nil
                }
                self.isGoogleSigningIn = false
                self.isAppleSigningIn = false
            }
        }
    }

    func signInWithGoogle() {
        guard FirebaseApp.app() != nil else {
            errorMessage = "\(AppConfig.Firebase.serviceInfoFilename).plist is missing, so Google sign-in is unavailable."
            return
        }

        guard let clientID = FirebaseApp.app()?.options.clientID else {
            errorMessage = "Firebase client ID is missing from the app configuration."
            return
        }

        guard let presenter = topViewController() else {
            errorMessage = "Could not find a view controller to present Google sign-in."
            return
        }

        errorMessage = nil
        isGoogleSigningIn = true

        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.signIn(withPresenting: presenter) { [weak self] result, error in
            guard let self else { return }

            if let error {
                Task { @MainActor in
                    self.errorMessage = error.localizedDescription
                    self.isGoogleSigningIn = false
                }
                return
            }

            guard
                let user = result?.user,
                let idToken = user.idToken?.tokenString
            else {
                Task { @MainActor in
                    self.errorMessage = "Google sign-in did not return a valid token."
                    self.isGoogleSigningIn = false
                }
                return
            }

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: user.accessToken.tokenString
            )

            Auth.auth().signIn(with: credential) { _, error in
                Task { @MainActor in
                    if let error {
                        self.errorMessage = error.localizedDescription
                        self.isGoogleSigningIn = false
                    } else {
                        self.errorMessage = nil
                        self.isGoogleSigningIn = false
                    }
                }
            }
        }
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = randomNonceString()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)
        errorMessage = nil
        isAppleSigningIn = true
    }

    func handleAppleCompletion(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .failure(error):
            errorMessage = error.localizedDescription
            isAppleSigningIn = false
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                errorMessage = "Apple sign-in did not return an Apple ID credential."
                isAppleSigningIn = false
                return
            }

            guard let nonce = currentNonce else {
                errorMessage = "Apple sign-in state is invalid. Please try again."
                isAppleSigningIn = false
                return
            }

            guard let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8) else {
                errorMessage = "Apple sign-in did not return a valid identity token."
                isAppleSigningIn = false
                return
            }

            let firebaseCredential = OAuthProvider.appleCredential(
                withIDToken: idToken,
                rawNonce: nonce,
                fullName: credential.fullName
            )

            Auth.auth().signIn(with: firebaseCredential) { [weak self] _, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.errorMessage = error.localizedDescription
                    } else {
                        self.errorMessage = nil
                    }
                    self.isAppleSigningIn = false
                    self.currentNonce = nil
                }
            }
        }
    }

    private func topViewController(base: UIViewController? = nil) -> UIViewController? {
        let root = base ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController

        if let navigationController = root as? UINavigationController {
            return topViewController(base: navigationController.visibleViewController)
        }
        if let tabBarController = root as? UITabBarController {
            return topViewController(base: tabBarController.selectedViewController)
        }
        if let presented = root?.presentedViewController {
            return topViewController(base: presented)
        }
        return root
    }

    private func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.map { String(format: "%02x", $0) }.joined()
    }

    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length

        while remainingLength > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
                }
                return random
            }

            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }

                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }

        return result
    }
}
