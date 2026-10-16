import Foundation

/// Opens a window whose scene identity is represented by a UUID.
///
/// This is useful for document, workspace, profile, and other resource windows
/// while allowing platforms without multiple-window support to expose a safe
/// no-op action through the same environment API.
public struct OpenIdentifiedWindowAction: Sendable {
    private let handler: @MainActor @Sendable (UUID) -> Void

    public init(handler: @escaping @MainActor @Sendable (UUID) -> Void = { _ in }) {
        self.handler = handler
    }

    @MainActor public func callAsFunction(_ id: UUID) {
        handler(id)
    }
}

public extension EnvironmentValues {
    var openIdentifiedWindow: OpenIdentifiedWindowAction {
        let openWindow = openWindow
        return OpenIdentifiedWindowAction { id in openWindow(value: id) }
    }
}
