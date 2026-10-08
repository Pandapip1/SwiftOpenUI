import Foundation

/// A view that handles URLs delivered to its scene.
public struct OpenURLHandlingView<Content: View>: View {
    public let content: Content
    public let action: (URL) -> Void

    public var body: Content { content }
}

extension View {
    /// Registers an action for URLs delivered to the application.
    public func onOpenURL(perform action: @escaping (URL) -> Void) -> some View {
        OpenURLHandlingView(content: self, action: action)
    }
}
