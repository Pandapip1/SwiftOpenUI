public extension View {
    /// Allows users to select and copy textual content on platforms that
    /// provide text selection.
    func copyableText() -> some View {
        textSelection(.enabled)
    }
}
