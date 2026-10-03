import Foundation

/// Platform services core views need but cannot implement themselves. Each backend installs real implementations
/// when it starts (see `GTK4Backend.run`); until then the defaults do nothing.
public enum SystemServices {
    /// Puts text on the system clipboard.
    nonisolated(unsafe) public static var copyToClipboard: (String) -> Void = { _ in }
    /// Opens a URL in the user's default handler (usually the web browser).
    nonisolated(unsafe) public static var openURL: (URL) -> Void = { _ in }
}
