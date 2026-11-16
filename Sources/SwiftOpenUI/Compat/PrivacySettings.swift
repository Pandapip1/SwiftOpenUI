import Foundation

/// Where the user grants a privacy permission once an app can no longer ask
/// for it. Same API as the SwiftUI backend's. Desktop Linux has no per-app
/// local-network permission, and camera access goes through the portal, which
/// asks each time, so there is no settings page to open.
public enum PrivacySettings {
    public enum Area: Sendable {
        case localNetwork
        case camera
    }

    public static func location(of area: Area) -> String {
        "your system’s privacy settings"
    }

    public static func canOpen(_ area: Area) -> Bool { false }

    @MainActor
    public static func open(_ area: Area) {}
}
