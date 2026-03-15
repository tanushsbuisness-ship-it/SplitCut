import SwiftUI
import SafariServices

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: config)
        controller.preferredBarTintColor = nil
        controller.preferredControlTintColor = nil
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        // No dynamic updates needed; if URL changes, SwiftUI will recreate the controller.
    }
}

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
// For macOS AppKit targets, you could provide an alternative implementation if needed.
#endif
