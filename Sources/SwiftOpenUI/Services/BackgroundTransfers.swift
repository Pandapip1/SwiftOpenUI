import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// HTTP transfers that keep going while the app is not in the foreground.
///
/// One API on every backend. On iOS, iPadOS, tvOS and visionOS (SwiftUI
/// backend) it is a background `URLSession`, so the system carries transfers
/// on while the app is suspended and wakes it when they finish (see
/// `handlesBackgroundTransfers`). Desktop processes keep running when not in
/// front, so the portable renderers (GTK) and macOS use an ordinary session.
public final class BackgroundTransferSession: Sendable {
    public static let shared = BackgroundTransferSession()
    /// The background session's identifier (for the app's scene).
    public static let identifier = "swiftopenui.background-transfers"

    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.httpMaximumConnectionsPerHost = 8
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
    }

    /// The response to `request`, delivered even if the app was suspended meanwhile.
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }

    /// Waits until the system has delivered every event of a background
    /// wake-up. Nothing to wait for where transfers never run suspended.
    public func finishEvents() async {}
}

extension Scene {
    /// Lets the system wake the app for finished background transfers
    /// (`BackgroundTransferSession`). Nothing to do where they never run
    /// suspended.
    public func handlesBackgroundTransfers() -> Self { self }
}
