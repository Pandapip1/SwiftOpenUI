#if canImport(SwiftUI)
import SwiftUI
import Foundation
import Synchronization

/// HTTP transfers that keep going while the app is not in the foreground.
/// On iOS, iPadOS, tvOS and visionOS a background `URLSession` (the system
/// carries transfers on while the app is suspended and wakes it when they
/// finish, see `handlesBackgroundTransfers`); on macOS, whose processes keep
/// running, an ordinary session. Same API as the portable implementation.
public final class BackgroundTransferSession: Sendable {
    public static let shared = BackgroundTransferSession()
    public static let identifier = "swiftopenui.background-transfers"

    private let session: URLSession
    private let events: TransferEvents?

    private init() {
        #if os(macOS)
        let configuration = URLSessionConfiguration.ephemeral
        events = nil
        #else
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = true
        let events = TransferEvents()
        self.events = events
        #endif
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.httpMaximumConnectionsPerHost = 8
        configuration.timeoutIntervalForRequest = 20
        #if os(macOS)
        session = URLSession(configuration: configuration)
        #else
        session = URLSession(configuration: configuration, delegate: events, delegateQueue: nil)
        #endif
    }

    /// The response to `request`, delivered even if the app was suspended meanwhile.
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let events else { return try await session.data(for: request) }
        // Background sessions run download tasks only; the body comes back as a file.
        let task = session.downloadTask(with: request)
        let identifier = task.taskIdentifier
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                events.register(identifier, continuation)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    /// Waits until the system has delivered every event of a background wake-up.
    public func finishEvents() async {
        guard let events else { return }
        await events.waitForEventsToFinish()
    }
}

/// The background session's delegate: completes each transfer's continuation.
private final class TransferEvents: NSObject, URLSessionDownloadDelegate, Sendable {
    private struct State {
        var pending: [Int: CheckedContinuation<(Data, URLResponse), any Error>] = [:]
        var bodies: [Int: Data] = [:]
        var finishWaiters: [CheckedContinuation<Void, Never>] = []
    }
    private let state = Mutex(State())

    func register(_ task: Int, _ continuation: CheckedContinuation<(Data, URLResponse), any Error>) {
        state.withLock { $0.pending[task] = continuation }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // The file is removed when this returns: read it now.
        let body = (try? Data(contentsOf: location)) ?? Data()
        let identifier = downloadTask.taskIdentifier
        state.withLock { $0.bodies[identifier] = body }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let identifier = task.taskIdentifier
        let (continuation, body) = state.withLock { state in
            (state.pending.removeValue(forKey: identifier), state.bodies.removeValue(forKey: identifier))
        }
        guard let continuation else { return }
        if let error {
            continuation.resume(throwing: error)
        } else if let response = task.response {
            continuation.resume(returning: (body ?? Data(), response))
        } else {
            continuation.resume(throwing: URLError(.badServerResponse))
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let waiters = state.withLock { state in
            let waiters = state.finishWaiters
            state.finishWaiters.removeAll()
            return waiters
        }
        for waiter in waiters { waiter.resume() }
    }

    func waitForEventsToFinish() async {
        await withCheckedContinuation { continuation in
            state.withLock { $0.finishWaiters.append(continuation) }
        }
    }
}

public extension Scene {
    /// Lets the system wake the app for finished background transfers
    /// (`BackgroundTransferSession`) and waits until their events are handled.
    @SceneBuilder
    func handlesBackgroundTransfers() -> some Scene {
        #if os(iOS)
        backgroundTask(.urlSession(BackgroundTransferSession.identifier)) {
            await BackgroundTransferSession.shared.finishEvents()
        }
        #else
        self
        #endif
    }
}
#endif
