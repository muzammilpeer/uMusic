import SwiftUI

extension View {
    @ViewBuilder
    func uMusicTextInputBehavior() -> some View {
        #if os(iOS)
        self
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .scrollDismissesKeyboard(.interactively)
        #else
        self.autocorrectionDisabled(true)
        #endif
    }
}
