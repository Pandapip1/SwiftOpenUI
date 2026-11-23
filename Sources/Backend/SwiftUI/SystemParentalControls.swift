#if canImport(SwiftUI)
import Foundation
#if canImport(DeclaredAgeRange)
import DeclaredAgeRange
#endif
#if canImport(PermissionKit)
import PermissionKit
#endif
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The operating system's parental controls for the current user, and its
/// "ask a parent" flow. Apps have no passcode of their own: the parent's
/// authority is the system's. Same API as the core (GTK, Win32) one.
public enum SystemParentalControls {
    public enum Status: Sendable, Equatable {
        /// The system reports no parental controls for this user.
        case notSupervised
        /// A parent manages this user. `allowsInstallingApps`: whether the
        /// parent lets them install software themselves. `contentAgeLimit`:
        /// the highest content age the parent allows, when the system says.
        case supervised(allowsInstallingApps: Bool, contentAgeLimit: Int?)
        /// The system cannot say (no API, not shared, not available here).
        case unavailable
    }

    public enum Request: Sendable, Equatable {
        /// The question went to the parent; its answer arrives later on
        /// `parentResponses()` with this id.
        case sent(id: UUID)
        /// This system has no way to ask a parent.
        case unavailable
    }

    public struct ParentResponse: Sendable, Equatable {
        public let requestID: UUID
        public let approved: Bool

        public init(requestID: UUID, approved: Bool) {
            self.requestID = requestID
            self.approved = approved
        }
    }

    /// Apple: Declared Age Range. A shared range whose
    /// `activeParentalControls` is non-empty, or which a guardian declared,
    /// means supervised. Screen Time content restrictions are not readable
    /// without the Family Controls entitlement, so no content limit is given.
    @MainActor
    public static func status() async -> Status {
        #if canImport(DeclaredAgeRange) && (os(iOS) || os(macOS) || os(visionOS))
        guard #available(iOS 26.0, macOS 26.0, visionOS 26.0, *) else { return .unavailable }
        do {
            #if os(macOS)
            guard let app = NSApp, let window = app.keyWindow ?? app.mainWindow ?? app.windows.first else { return .unavailable }
            let response = try await AgeRangeService.shared.requestAgeRange(ageGates: 13, 16, 18, in: window)
            #else
            guard let presenter = topViewController() else { return .unavailable }
            let response = try await AgeRangeService.shared.requestAgeRange(ageGates: 13, 16, 18, in: presenter)
            #endif
            switch response {
            case .declinedSharing:
                return .unavailable
            case .sharing(let range):
                let managed = !range.activeParentalControls.isEmpty || range.ageRangeDeclaration == .guardianDeclared
                return managed ? .supervised(allowsInstallingApps: false, contentAgeLimit: nil) : .notSupervised
            @unknown default:
                return .unavailable
            }
        } catch {
            return .unavailable
        }
        #else
        return .unavailable
        #endif
    }

    /// Asks the parent, through the system, to approve `description`.
    /// Apple: PermissionKit's significant-change question (iOS, macOS and
    /// visionOS 26.2), the documented topic for a change in what an app
    /// does; the parent answers on their own device.
    @MainActor
    public static func askParent(_ description: String) async -> Request {
        #if canImport(PermissionKit) && (os(iOS) || os(macOS) || os(visionOS))
        guard #available(iOS 26.2, macOS 26.2, visionOS 26.2, *) else { return .unavailable }
        let question = PermissionQuestion<SignificantAppUpdateTopic>(
            significantAppUpdateTopic: SignificantAppUpdateTopic(description: description)
        )
        do {
            #if os(macOS)
            guard let app = NSApp, let window = app.keyWindow ?? app.mainWindow ?? app.windows.first else { return .unavailable }
            try await AskCenter.shared.ask(question, in: window)
            #else
            guard let presenter = topViewController() else { return .unavailable }
            try await AskCenter.shared.ask(question, in: presenter)
            #endif
            return .sent(id: question.id)
        } catch {
            return .unavailable
        }
        #else
        return .unavailable
        #endif
    }

    /// Parents' answers to `askParent` questions, as they arrive. Listen for
    /// the app's lifetime: an answer can come long after the question.
    public static func parentResponses() -> AsyncStream<ParentResponse> {
        AsyncStream { continuation in
            #if canImport(PermissionKit) && (os(iOS) || os(macOS) || os(visionOS))
            guard #available(iOS 26.2, macOS 26.2, visionOS 26.2, *) else {
                continuation.finish()
                return
            }
            let task = Task {
                for await response in AskCenter.shared.responses(for: SignificantAppUpdateTopic.self) {
                    continuation.yield(ParentResponse(
                        requestID: response.question.id,
                        approved: response.choice.answer == PermissionChoice.approve.answer
                    ))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
            #else
            continuation.finish()
            #endif
        }
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
