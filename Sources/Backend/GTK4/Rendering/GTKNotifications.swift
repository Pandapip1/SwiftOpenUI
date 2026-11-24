import CGTK
import Foundation
import PlatformSupport

/// Local notifications on the GTK backend: GNotification, which GLib sends
/// through the desktop's notification portal when there is one (Flatpak,
/// GNOME, KDE) and to the notification daemon otherwise. Desktops don't ask
/// for permission per app, so notifications count as authorized; the user
/// turns them off in the desktop's settings.
struct GTKNotificationCenter: LocalNotificationCenter {
    func authorization() async -> NotificationAuthorization { .authorized }
    func requestAuthorization() async -> NotificationAuthorization { .authorized }

    func post(_ notification: LocalNotification) async throws {
        await MainActor.run {
            guard let application = g_application_get_default(),
                  let gNotification = g_notification_new(notification.title) else { return }
            g_notification_set_body(gNotification, notification.body)
            g_application_send_notification(application, notification.identifier, gNotification)
            g_object_unref(UnsafeMutableRawPointer(gNotification))
        }
    }
}
