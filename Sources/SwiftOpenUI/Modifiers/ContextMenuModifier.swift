/// Attaches a context menu to the content, triggered by right-click.
/// GTK4: button-3 gesture. Win32: WM_RBUTTONUP. Web: contextmenu event.
import Foundation

@_spi(SwiftOpenUIBackend)
public struct _ContextMenuView<Content: View, MenuContent: View>: View, PrimitiveView {
    public typealias Body = Never
    public let content: Content
    public let menuContent: MenuContent
    /// A fresh menu primitive is also a fresh action environment. Backends use
    /// this token to replace native menu closures when a view rebuilds even if
    /// the visible menu labels have not changed.
    @_spi(SwiftOpenUIBackend)
    public let _menuIdentity: UUID

    @_spi(SwiftOpenUIBackend)
    public init(content: Content, menuContent: MenuContent) {
        self.content = content
        self.menuContent = menuContent
        self._menuIdentity = UUID()
    }

    /// The backend-facing action representation extracted from the SwiftUI view tree.
    /// Keeping this derived preserves the exact public `@ViewBuilder` API while allowing
    /// native backends to build their platform menus.
    @_spi(SwiftOpenUIBackend)
    public var menuElements: [MenuElement] {
        AlertActions.menuElements(from: menuContent)
    }

    public var body: Never { fatalError() }
}

extension View {
    /// Adds a context menu to this view with the same view-builder shape as SwiftUI.
    public func contextMenu<MenuContent: View>(
        @ViewBuilder menuItems: () -> MenuContent
    ) -> some View {
        _ContextMenuView(content: self, menuContent: menuItems())
    }
}
