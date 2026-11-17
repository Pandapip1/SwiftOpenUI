#if canImport(SwiftUI)
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Where the user grants a privacy permission once an app can no longer ask
/// for it. Apps describe and open the place through this one API; how each
/// platform does it lives here.
public enum PrivacySettings {
    public enum Area: Sendable {
        case localNetwork
        case camera
    }

    /// The place to change `area`, for sentences such as
    /// "Allow it in \(location(of: .localNetwork))".
    public static func location(of area: Area) -> String {
        #if os(macOS)
        switch area {
        case .localNetwork: "System Settings › Privacy & Security › Local Network"
        case .camera: "System Settings › Privacy & Security › Camera"
        }
        #elseif os(tvOS)
        "Settings"
        #else
        "this app’s page in Settings"
        #endif
    }

    /// Whether `open(_:)` can take the user there.
    public static func canOpen(_ area: Area) -> Bool {
        #if os(tvOS)
        false
        #else
        true
        #endif
    }

    @MainActor
    public static func open(_ area: Area) {
        #if os(macOS)
        let anchor = switch area {
        case .localNetwork: "Privacy_LocalNetwork"
        case .camera: "Privacy_Camera"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
        #elseif os(iOS) || os(visionOS)
        // The app's own page, which holds its Local Network and Camera switches.
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}
#endif
