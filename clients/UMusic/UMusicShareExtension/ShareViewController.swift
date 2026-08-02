import Security
import Social
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#else
import AppKit
#endif

final class ShareViewController: SLComposeServiceViewController {
    private let importer = SharedURLImporter()
    private var sharedURL: URL?
    private var submitting = false

    override func presentationAnimationDidFinish() {
        super.presentationAnimationDidFinish()
        #if os(iOS)
        navigationItem.rightBarButtonItem?.title = "Download"
        #endif
        textView.isEditable = false
        loadSharedURL()
    }

    override func isContentValid() -> Bool {
        sharedURL.map(Self.isSupportedYouTubeURL) == true && !submitting
    }

    override func didSelectPost() {
        guard let sharedURL, !submitting else { return }
        submitting = true
        validateContent()
        Task {
            do {
                try await importer.submit(sharedURL)
                extensionContext?.completeRequest(returningItems: nil)
            } catch {
                await MainActor.run {
                    self.submitting = false
                    self.validateContent()
                    self.show(error.localizedDescription)
                }
            }
        }
    }

    override func didSelectCancel() {
        extensionContext?.cancelRequest(withError: CancellationError())
    }

    private func loadSharedURL() {
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        let providers = items.reduce(into: [NSItemProvider]()) { result, item in
            result.append(contentsOf: item.attachments ?? [])
        }
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.url.identifier)
                || $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
        }) else {
            show("No web link was shared.")
            return
        }
        let type = provider.hasItemConformingToTypeIdentifier(UTType.url.identifier)
            ? UTType.url.identifier : UTType.plainText.identifier
        provider.loadItem(forTypeIdentifier: type, options: nil) { [weak self]
            (item: NSSecureCoding?, _: Error?) in
            let url = (item as? URL)
                ?? (item as? NSURL).map { $0 as URL }
                ?? (item as? String).flatMap(URL.init(string:))
            Task { @MainActor in
                guard let self else { return }
                self.sharedURL = url
                #if os(iOS)
                self.textView.text = url?.absoluteString ?? "YouTube URL"
                #else
                self.textView.string = url?.absoluteString ?? "YouTube URL"
                #endif
                if url.map(Self.isSupportedYouTubeURL) != true {
                    self.show("Share a youtube.com or youtu.be link.")
                }
                #if os(iOS)
                self.navigationItem.rightBarButtonItem?.title = "Download"
                #endif
                self.validateContent()
            }
        }
    }

    private static func isSupportedYouTubeURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else {
            return false
        }
        return host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com")
    }

    private func show(_ message: String) {
        #if os(iOS)
        let alert = UIAlertController(title: "uMusic", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
        #else
        let alert = NSAlert()
        alert.messageText = "uMusic"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        #endif
    }
}

private struct SharedURLImporter {
    private let accessGroup = "3S2DR3CGY4.app.umusic.shared"

    func submit(_ url: URL) async throws {
        guard let token = try loadToken() else { throw ShareImportError.signInRequired }
        guard let value = Bundle.main.object(forInfoDictionaryKey: "UMusicServerURL") as? String,
              let server = URL(string: value) else { throw ShareImportError.configuration }
        var request = URLRequest(url: server.appending(path: "api/v1/adapters/remote/"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "urls": url.absoluteString,
            "attested": true,
        ])
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ShareImportError.server }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ShareImportError.signInRequired
        }
        guard (200..<300).contains(http.statusCode) else { throw ShareImportError.server }
    }

    private func loadToken() throws -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "app.umusic.client",
            kSecAttrAccount: "device-token",
            kSecAttrAccessGroup: accessGroup,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ] as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw ShareImportError.credentials
        }
        return String(data: data, encoding: .utf8)
    }
}

private enum ShareImportError: LocalizedError {
    case signInRequired, configuration, credentials, server

    var errorDescription: String? {
        switch self {
        case .signInRequired: "Open uMusic and sign in once, then share the link again."
        case .configuration: "The uMusic server is not configured."
        case .credentials: "The saved uMusic login could not be read."
        case .server: "The server could not queue this link. Try again later."
        }
    }
}
