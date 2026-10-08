/// A type that specifies the appearance and interaction of a `TabView`.
public protocol TabViewStyle {}

/// A tab style that can adapt between a sidebar and a tab bar.
public struct SidebarAdaptableTabViewStyle: TabViewStyle {
    public init() {}
}

extension TabViewStyle where Self == SidebarAdaptableTabViewStyle {
    public static var sidebarAdaptable: SidebarAdaptableTabViewStyle { .init() }
}

/// The primitive produced by SwiftUI's `tabViewStyle(_:)` modifier.
public struct TabViewStyleView<Content: View, Style: TabViewStyle>: View, PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let style: Style
    public var body: Never { fatalError("TabViewStyleView is a primitive view") }
}

extension View {
    public func tabViewStyle<Style: TabViewStyle>(_ style: Style) -> TabViewStyleView<Self, Style> {
        TabViewStyleView(content: self, style: style)
    }
}
