import Foundation
import Synchronization
#if canImport(UserNotifications) && !os(tvOS)
import UserNotifications
#endif

/// A notification posted by the app itself, shown by the system.
public struct LocalNotification: Sendable, Equatable {
    /// Posting again with the same identifier replaces the earlier one.
    public var identifier: String
    public var title: String
    public var body: String
    /// Notifications with the same thread are grouped.
    public var thread: String?

    public init(identifier: String, title: String, body: String, thread: String? = nil) {
        self.identifier = identifier
        self.title = title
        self.body = body
        self.thread = thread
    }
}

/// Whether the system lets the app show notifications.
public enum NotificationAuthorization: Sendable, Equatable {
    /// Not asked yet.
    case notDetermined
    /// The user said no (or turned them off in settings).
    case denied
    case authorized
    /// This platform shows none (tvOS), or no backend provides them.
    case unsupported
}

/// Where notifications go on this platform.
public protocol LocalNotificationCenter: Sendable {
    func authorization() async -> NotificationAuthorization
    /// Asks the user, if not asked yet; returns the answer.
    func requestAuthorization() async -> NotificationAuthorization
    func post(_ notification: LocalNotification) async throws
}

/// Local notifications, one API on every platform: the system's
/// notification center on iOS, iPadOS, macOS and visionOS; on Linux the
/// GTK backend installs the desktop's (GNotification, through the portal
/// where there is one). tvOS shows no notifications.
public enum LocalNotifications {
    private static let installed = Mutex<(any LocalNotificationCenter)?>(nil)

    /// The center in use.
    public static var center: any LocalNotificationCenter {
        if let center = installed.withLock({ $0 }) { return center }
        #if canImport(UserNotifications) && !os(tvOS)
        return SystemNotificationCenter()
        #else
        return UnsupportedNotificationCenter()
        #endif
    }

    /// A backend installs its platform's center (the GTK backend at launch).
    public static func install(_ center: any LocalNotificationCenter) {
        installed.withLock { $0 = center }
    }
}

/// No notifications on this platform.
public struct UnsupportedNotificationCenter: LocalNotificationCenter {
    public init() {}
    public func authorization() async -> NotificationAuthorization { .unsupported }
    public func requestAuthorization() async -> NotificationAuthorization { .unsupported }
    public func post(_ notification: LocalNotification) async throws {}
}

#if canImport(UserNotifications) && !os(tvOS)
/// UNUserNotificationCenter.
struct SystemNotificationCenter: LocalNotificationCenter {
    func authorization() async -> NotificationAuthorization {
        Self.map(await UNUserNotificationCenter.current().notificationSettings().authorizationStatus)
    }

    func requestAuthorization() async -> NotificationAuthorization {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        return Self.map(await center.notificationSettings().authorizationStatus)
    }

    func post(_ notification: LocalNotification) async throws {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        if let thread = notification.thread { content.threadIdentifier = thread }
        try await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: notification.identifier, content: content, trigger: nil)
        )
    }

    private static func map(_ status: UNAuthorizationStatus) -> NotificationAuthorization {
        switch status {
        case .notDetermined: .notDetermined
        case .denied: .denied
        // Authorized, provisional, and (on iOS) ephemeral all show notifications.
        default: .authorized
        }
    }
}
#endif
