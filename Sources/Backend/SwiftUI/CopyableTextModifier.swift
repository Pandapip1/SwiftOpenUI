#if canImport(SwiftUI)
import SwiftUI

public extension View {
    /// Allows users to select and copy textual content on platforms that
    /// provide text selection. Focus-only platforms preserve the content
    /// without applying an unavailable selection interaction.
    @ViewBuilder
    func copyableText() -> some View {
        #if os(tvOS)
        self
        #else
        textSelection(.enabled)
        #endif
    }
}
#endif
