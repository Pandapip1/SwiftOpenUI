import Foundation
import SwiftOpenUICore

@MainActor @preconcurrency
public struct WebView: View, PrimitiveView {
    public typealias Body = Never
    @_spi(SwiftOpenUIBackend) public let page: WebPage

    public init(_ page: WebPage) { self.page = page }
    /// Loads `url` in a page with its own non-persistent data store.
    public init(url: URL?) { page = WebPage(initialURL: url) }
    public var body: Never { fatalError("WebView is a primitive view") }
}
