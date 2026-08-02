import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var username = ""
    @State private var password = ""
    @State private var deviceName = ProcessInfo.processInfo.hostName
    @State private var signingIn = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField(AppConfiguration.productionServer.absoluteString, text: $session.serverText)
                        .textContentType(.URL)
                        #if os(iOS)
                        .keyboardType(.URL)
                        #endif
                }
                Section("Owner account") {
                    TextField("Username", text: $username).textContentType(.username)
                    SecureField("Password", text: $password).textContentType(.password)
                    TextField("Device name", text: $deviceName)
                }
                if let message = session.errorMessage {
                    Text(message).foregroundStyle(.red)
                }
                Button(signingIn ? "Connecting…" : "Connect device") {
                    signingIn = true
                    Task {
                        await session.signIn(
                            username: username, password: password, deviceName: deviceName
                        )
                        signingIn = false
                    }
                }
                .disabled(signingIn || username.isEmpty || password.isEmpty)
            }
            .navigationTitle("Connect to uMusic")
        }
        .frame(minWidth: 380, minHeight: 420)
    }
}
