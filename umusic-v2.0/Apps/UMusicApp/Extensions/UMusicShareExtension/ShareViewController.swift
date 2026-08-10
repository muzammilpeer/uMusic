#if canImport(UIKit)
import UIKit
import UniformTypeIdentifiers
import UMusicImportClient

/// Intentionally links only UMusicImportClient. It never downloads media or initializes the host app.
final class ShareViewController: UIViewController {
    private let urlLabel = UILabel()
    private let statusLabel = UILabel()
    private let sendButton = UIButton(type: .system)
    private var importRequest: ImportRequest?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        urlLabel.numberOfLines = 3
        statusLabel.numberOfLines = 2
        statusLabel.text = "Only send media you are authorized to import. Provider availability can change."
        sendButton.setTitle("Send to Server", for: .normal)
        sendButton.addTarget(self, action: #selector(send), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [urlLabel, statusLabel, sendButton])
        stack.axis = .vertical; stack.spacing = 16; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor), stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor), stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
        loadSharedURL()
    }

    private func loadSharedURL() {
        let providers = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem }.flatMap { $0.attachments ?? [] } ?? []
        Task {
            var candidates: [URL] = []
            for provider in providers {
                for type in [UTType.url.identifier, UTType.plainText.identifier] where provider.hasItemConformingToTypeIdentifier(type) {
                    if let item = try? await provider.loadItem(forTypeIdentifier: type), let url = item as? URL ?? (item as? String).flatMap(URL.init(string:)) { candidates.append(url) }
                }
            }
            await MainActor.run {
                do { let request = try ImportRequest(sourceURL: ImportURLPolicy.firstSupportedURL(in: candidates)); importRequest = request; urlLabel.text = request.sourceURL.absoluteString; sendButton.isEnabled = true }
                catch { statusLabel.text = "This link is not a supported YouTube or direct MP3 URL."; sendButton.isEnabled = false }
            }
        }
    }

    @objc private func send() {
        guard let request = importRequest else { return }
        sendButton.isEnabled = false
        Task {
            do {
                let handoff = try AppGroupImportHandoff(suiteName: "group.uk.muzammilpeer.umusic.v2")
                try await handoff.enqueue(request)
                await MainActor.run { extensionContext?.completeRequest(returningItems: nil) }
            } catch {
                await MainActor.run { statusLabel.text = "Unable to queue the import. Open uMusic and sign in, then try again."; sendButton.isEnabled = true }
            }
        }
    }
}
#endif
