#if canImport(SwiftUI)
import Foundation
#if canImport(DeclaredAgeRange)
import DeclaredAgeRange
#endif
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The platform's answer to "how old is the person using this device?",
/// asked at the moment a decision needs it. Nothing here caches or stores
/// the answer: age changes over time, and the platform is the authority.
/// Same API as the core (GTK, Win32) implementation.
public enum AgeAssurance {
    public enum Answer: Sendable, Equatable {
        /// The age range the platform shared, bounds inclusive and in years.
        /// Either bound can be open. The bounds are no finer than the gates
        /// that were asked for.
        case range(lowerBound: Int?, upperBound: Int?)
        /// The person, or whoever manages their account, chose not to share.
        /// Not an age and not "unavailable": what it means is the app's call.
        case declined
        /// This platform, account or region has no age source right now.
        case unavailable
    }

    /// Asks the platform now. `gates` are the ages the decision cares about
    /// (at most three are used, the smallest first); the platform may show
    /// its own consent UI.
    ///
    /// Apple: Declared Age Range (iOS, iPadOS, visionOS and macOS 26). It can
    /// throw "not available" (some regions, and macOS in practice), which is
    /// reported as `.unavailable`.
    @MainActor
    public static func currentAgeRange(gates: [Int]) async -> Answer {
        let sorted = Array(Set(gates.filter { $0 > 0 })).sorted()
        guard let first = sorted.first else { return .unavailable }
        let second = sorted.count > 1 ? sorted[1] : nil
        let third = sorted.count > 2 ? sorted[2] : nil
        #if canImport(DeclaredAgeRange) && (os(iOS) || os(macOS) || os(visionOS))
        guard #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) else { return .unavailable }
        do {
            #if os(macOS)
            guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first else {
                return .unavailable
            }
            let response = try await AgeRangeService.shared.requestAgeRange(
                ageGates: first, second, third, in: window
            )
            #else
            guard let presenter = topViewController() else { return .unavailable }
            let response = try await AgeRangeService.shared.requestAgeRange(
                ageGates: first, second, third, in: presenter
            )
            #endif
            switch response {
            case .declinedSharing:
                return .declined
            case .sharing(let range):
                return .range(lowerBound: range.lowerBound, upperBound: range.upperBound)
            @unknown default:
                return .unavailable
            }
        } catch {
            return .unavailable
        }
        #else
        _ = (first, second, third)
        return .unavailable
        #endif
    }

    #if canImport(UIKit) && (os(iOS) || os(visionOS))
    @MainActor
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController { controller = presented }
        return controller
    }
    #endif
}
#endif
