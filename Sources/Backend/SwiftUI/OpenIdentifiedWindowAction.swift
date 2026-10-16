#if canImport(SwiftUI)
import Foundation
import SwiftUI

/// Opens a window whose scene identity is represented by a UUID.
///
/// Platforms without multiple-window support expose a no-op action, allowing
/// shared application UI to select its navigation policy without referencing
/// platform-specific SwiftUI availability.
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
        #if os(tvOS)
        OpenIdentifiedWindowAction()
        #else
        OpenIdentifiedWindowAction { id in openWindow(value: id) }
        #endif
    }
}
#endif
