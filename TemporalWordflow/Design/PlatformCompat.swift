import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

// Thin shims so every view file compiles on macOS for static checking while
// still using the iOS-only modifiers on device.

extension View {
    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder
    func usernameField() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .keyboardType(.asciiCapable)
            .textContentType(.username)
        #else
        self.autocorrectionDisabled(true)
        #endif
    }

    @ViewBuilder
    func displayNameField() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.words)
            .autocorrectionDisabled(true)
            .textContentType(.nickname)
        #else
        self.autocorrectionDisabled(true)
        #endif
    }

    /// `autocomplete="current-password"` / `"new-password"` on the web forms:
    /// lets iOS offer a saved credential, or generate a strong one on sign-up.
    @ViewBuilder
    func passwordField(isNew: Bool) -> some View {
        #if os(iOS)
        self.textContentType(isNew ? .newPassword : .password)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
        #else
        self.autocorrectionDisabled(true)
        #endif
    }

    @ViewBuilder
    func interactiveDismissKeyboard() -> some View {
        #if os(iOS)
        self.scrollDismissesKeyboard(.interactively)
        #else
        self
        #endif
    }

    /// `.contentTransition(.numericText())` reads well for the live countdowns
    /// but is only worth the cost where the value actually ticks.
    @ViewBuilder
    func tickingNumber() -> some View {
        self.monospacedDigit().contentTransition(.numericText())
    }
}
