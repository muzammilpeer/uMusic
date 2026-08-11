import Observation
import SwiftUI
import UMusicCore

@MainActor
@Observable
public final class AuthenticationViewModel {
    public var serverURL = ""
    public var username = ""
    public var password = ""
    public var keepSignedIn = true
    public var allowsInsecureLocalhost = false
    public private(set) var state: AuthenticationState = .signedOut
    public private(set) var isRestoringSession = true

    private let authentication: any AuthenticationManaging

    public init(authentication: any AuthenticationManaging) {
        self.authentication = authentication
    }

    public var isWorking: Bool { state == .validatingServer || state == .authenticating }

    public var failure: AuthenticationFailure? {
        switch state {
        case .failed(let failure), .offline(let failure): failure
        default: nil
        }
    }

    public func observe() async {
        var snapshots = authentication.snapshots.makeAsyncIterator()
        // Authentication coordinators seed their stream with the current state.
        // Consume that seed while the launch screen is still visible, then wait
        // for restore() to publish the authoritative Keychain restoration result.
        if let initialState = await snapshots.next() {
            state = initialState
        }
        await authentication.restore()
        if let restoredState = await snapshots.next() {
            state = restoredState
        }
        isRestoringSession = false
        while let snapshot = await snapshots.next() {
            state = snapshot
        }
    }

    public func connect() async {
        let submittedPassword = password
        password = ""
        await authentication.connect(
            serverURL: serverURL,
            username: username,
            password: submittedPassword,
            keepSignedIn: keepSignedIn,
            allowsInsecureLocalhost: allowsInsecureLocalhost
        )
    }
}

public struct OnboardingView: View {
    @Bindable private var model: AuthenticationViewModel

    public init(model: AuthenticationViewModel) { self.model = model }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Server URL", text: $model.serverURL, prompt: Text("https://music.example.com"))
                        .textContentType(.URL)
                        .modifier(NormalizedTextInput())
                    TextField("Username", text: $model.username)
                        .textContentType(.username)
                        .modifier(NormalizedTextInput())
                    SecureField("Password", text: $model.password)
                        .textContentType(.password)
                    Toggle("Keep Me Signed In", isOn: $model.keepSignedIn)
                } header: {
                    Text("Connect to your private uMusic server")
                } footer: {
                    Text("Your password is used only to create a session. Persistent session tokens are stored in Keychain.")
                }

                DisclosureGroup("Development Options") {
                    Toggle("Allow HTTP for localhost", isOn: $model.allowsInsecureLocalhost)
                    Text("Never enable this for a remote server.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let failure = model.failure {
                    Section("Connection Problem") {
                        Text(failure.message)
                        if let requestID = failure.requestID {
                            Text("Request ID: \(requestID)")
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }

                Button {
                    Task { await model.connect() }
                } label: {
                    if model.isWorking { ProgressView() } else { Text("Connect") }
                }
                .disabled(model.isWorking || model.serverURL.isEmpty || model.username.isEmpty || model.password.isEmpty)
            }
            .formStyle(.grouped)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Welcome to uMusic")
        }
    }
}

private struct NormalizedTextInput: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
#if os(iOS)
        content
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
#else
        content
#endif
    }
}

public struct UMusicRootView: View {
    private let client: any UMusicClient
    @State private var authenticationModel: AuthenticationViewModel

    public init(client: any UMusicClient) {
        self.client = client
        _authenticationModel = State(initialValue: AuthenticationViewModel(authentication: client.authentication))
    }

    public var body: some View {
        Group {
            if authenticationModel.isRestoringSession {
                LaunchLoadingView()
            } else {
                authenticatedContent
            }
        }
        .task { await authenticationModel.observe() }
    }

    @ViewBuilder
    private var authenticatedContent: some View {
        switch authenticationModel.state {
            case .authenticated:
                AppShellView(authentication: client.authentication, library: client.library, playback: client.playback, offline: client.offline, playlists: client.playlists, personalization: client.personalization, context: client.context, calendarPreferences: client.calendarPreferences, diagnostics: client.diagnostics)
            case .validatingServer, .authenticating:
                ProgressView("Connecting securely…")
            default:
                OnboardingView(model: authenticationModel)
        }
    }
}

private struct LaunchLoadingView: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "music.note")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(.tint)
            Text("uMusic")
                .font(.largeTitle.bold())
            ProgressView("Restoring your session…")
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("uMusic, restoring your session")
    }
}
