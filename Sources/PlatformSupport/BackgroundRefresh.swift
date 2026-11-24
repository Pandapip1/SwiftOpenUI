import Foundation
#if canImport(BackgroundTasks) && !os(macOS)
import BackgroundTasks
#endif

/// Time the system gives the app for work while it isn't being used:
/// BackgroundTasks on iOS, iPadOS, tvOS and visionOS (app refresh for short
/// checks, processing for heavier work, optionally only while charging);
/// elsewhere (macOS, Linux, Windows) a timer while the app runs. One API: the
/// app registers a handler per identifier at launch and asks for the next
/// window; the handler gets a deadline, and its task is cancelled if the
/// system takes the time back early.
public enum BackgroundRefresh {
    public enum Kind: Sendable, Equatable {
        /// A short check (iOS gives about 30 seconds).
        case refresh
        /// Heavier work, for minutes; `requiresExternalPower` waits for a
        /// charger.
        case processing(requiresExternalPower: Bool)

        /// How long a window of this kind lasts, as this platform grants it.
        var duration: Duration {
            switch self {
            case .refresh: .seconds(25)
            case .processing: .seconds(5 * 60)
            }
        }
    }

    /// One window: work until `deadline`. Cancellation means the system
    /// ended it early.
    public struct Window: Sendable {
        public let kind: Kind
        public let deadline: ContinuousClock.Instant
    }

    /// Does the window's work; returns whether it completed.
    public typealias Handler = @Sendable (Window) async -> Bool

    @MainActor private static var kinds: [String: Kind] = [:]
    @MainActor private static var timers: [String: Task<Void, Never>] = [:]
    @MainActor private static var handlers: [String: Handler] = [:]

    /// Registers the work for `identifier`. Call at launch, before the app
    /// finishes launching (iOS requires it), once per identifier. On iOS the
    /// identifier must be listed in `BGTaskSchedulerPermittedIdentifiers`.
    @MainActor
    public static func register(_ identifier: String, kind: Kind, handler: @escaping Handler) {
        kinds[identifier] = kind
        handlers[identifier] = handler
        #if canImport(BackgroundTasks) && !os(macOS)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            MainActor.assumeIsolated { run(task, kind: kind, handler: handler) }
        }
        #endif
    }

    /// Asks for the next window for `identifier`, no earlier than `earliest`.
    /// The system decides when it actually comes (on iOS, based on how the
    /// app is used); a later request replaces an earlier one.
    @MainActor
    public static func schedule(_ identifier: String, earliest: Date) throws {
        guard let kind = kinds[identifier] else { throw Failure.notRegistered }
        #if canImport(BackgroundTasks) && !os(macOS)
        let request: BGTaskRequest
        switch kind {
        case .refresh:
            request = BGAppRefreshTaskRequest(identifier: identifier)
        case .processing(let requiresExternalPower):
            let processing = BGProcessingTaskRequest(identifier: identifier)
            processing.requiresExternalPower = requiresExternalPower
            processing.requiresNetworkConnectivity = true
            request = processing
        }
        request.earliestBeginDate = earliest
        try BGTaskScheduler.shared.submit(request)
        #else
        guard let handler = handlers[identifier] else { throw Failure.notRegistered }
        timers[identifier]?.cancel()
        let wait = Duration.seconds(max(0, earliest.timeIntervalSinceNow))
        timers[identifier] = Task { @MainActor in
            do { try await Task.sleep(for: wait, tolerance: wait / 10 + .seconds(1)) } catch { return }
            let window = Window(kind: kind, deadline: .now + kind.duration)
            let work = Task { await handler(window) }
            // The window ends at its deadline here too.
            let limit = Task {
                try? await Task.sleep(until: window.deadline)
                work.cancel()
            }
            _ = await work.value
            limit.cancel()
        }
        #endif
    }

    /// Withdraws a requested window.
    @MainActor
    public static func cancel(_ identifier: String) {
        #if canImport(BackgroundTasks) && !os(macOS)
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        #else
        timers[identifier]?.cancel()
        timers[identifier] = nil
        #endif
    }

    public enum Failure: Error, Equatable {
        case notRegistered
    }

    #if canImport(BackgroundTasks) && !os(macOS)
    @MainActor
    private static func run(_ task: BGTask, kind: Kind, handler: @escaping Handler) {
        let window = Window(kind: kind, deadline: .now + kind.duration)
        let work = Task { await handler(window) }
        // The system takes the time back: cancel the work, which saves
        // what it finished and stops.
        task.expirationHandler = { work.cancel() }
        Task { @MainActor in
            let completed = await work.value
            task.setTaskCompleted(success: completed)
        }
    }
    #endif
}
