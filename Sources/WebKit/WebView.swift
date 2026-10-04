import Foundation
import SwiftOpenUI

@MainActor @preconcurrency
public struct WebView: View, PrimitiveView {
    public typealias Body = Never
    @_spi(SwiftOpenUIBackend) public let page: WebPage

    public init(_ page: WebPage) { self.page = page }
    public init(url: URL?) { page = WebPage(initialURL: url) }
    public var body: Never { fatalError("WebView is a primitive view") }
}
