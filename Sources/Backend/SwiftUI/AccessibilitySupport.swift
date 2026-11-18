#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// Accessibility building blocks with one API on every backend (the portable
// declaration is Sources/SwiftOpenUI/Views/AccessibilitySupport.swift). The
// standard accessibility modifiers, traits, environment values and
// `AccessibilityNotification` are SwiftUI's own here.

// MARK: - Motion

/// Whether the system asks for reduced motion, for code without an environment.
private enum SystemMotion {
    @MainActor static var reduces: Bool {
    #if canImport(UIKit)
    UIAccessibility.isReduceMotionEnabled
    #elseif canImport(AppKit)
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    #else
    false
    #endif
    }
}

/// `withAnimation`, or no animation when Reduce Motion is on: the change still
/// happens, at once.
@MainActor
public func withMotionAwareAnimation<Result>(_ animation: Animation = .default, _ body: () -> Result) -> Result {
    if SystemMotion.reduces { return body() }
    return withAnimation(animation, body)
}

public extension View {
    /// Animates changes of `value` with `animation`, or without animation when
    /// Reduce Motion is on. For movement, zooms, springs and parallax; colour
    /// and opacity changes can keep a plain `.animation`.
    func motionAwareAnimation<Value: Equatable>(_ animation: Animation?, value: Value) -> some View {
        modifier(MotionAwareAnimation(animation: animation, value: value))
    }

    /// `transition`, or `reduced` (a dissolve unless given) when Reduce Motion is on.
    func motionAwareTransition(_ transition: AnyTransition, reduced: AnyTransition = .opacity) -> some View {
        modifier(MotionAwareTransition(transition: transition, reduced: reduced))
    }
}

private struct MotionAwareAnimation<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation?
    let value: Value

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

private struct MotionAwareTransition: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let transition: AnyTransition
    let reduced: AnyTransition

    func body(content: Content) -> some View {
        content.transition(reduceMotion ? reduced : transition)
    }
}

// MARK: - Announcements

public extension View {
    /// Announces `message(value)` to assistive technology whenever `value`
    /// changes (nothing when it returns nil). For the result of something slow
    /// finishing: a switch that took effect or failed, a list that loaded.
    func announcesChange<Value: Equatable>(of value: Value,
                                           _ message: @escaping (Value) -> String?) -> some View {
        onChange(of: value) { _, newValue in
            if let text = message(newValue) {
                AccessibilityNotification.Announcement(text).post()
            }
        }
    }
}

// MARK: - Modal content

public extension View {
    /// Content drawn over the rest of the window that assistive technology
    /// must treat as modal: nothing behind it can be reached while it is
    /// shown, and the escape gesture (VoiceOver's two-finger scrub, Escape
    /// with a keyboard) runs `onDismiss`. For overlays that aren't presented
    /// as a sheet.
    func accessibilityModal(onDismiss: @escaping () -> Void) -> some View {
        modifier(AccessibilityModalModifier(onDismiss: onDismiss))
    }
}

private struct AccessibilityModalModifier: ViewModifier {
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape, onDismiss)
            #if os(macOS) || os(tvOS)
            .onExitCommand(perform: onDismiss)
            #endif
    }
}

// MARK: - Glass

public extension View {
    /// The background for chrome drawn over content (bars, banners, overlays
    /// on video): Liquid Glass on OS 26 (interactive for a control), a
    /// material before. When the user reduces transparency or increases
    /// contrast it is opaque instead, with a visible border, so whatever is
    /// behind never lowers the content's contrast.
    func glassBackground<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        modifier(GlassBackgroundModifier(shape: shape, interactive: interactive))
    }
}

private struct GlassBackgroundModifier<S: Shape>: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    let shape: S
    let interactive: Bool

    func body(content: Content) -> some View {
        if reduceTransparency || contrast == .increased {
            content
                .background(.background, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(contrast == .increased ? 0.6 : 0.15), lineWidth: 1))
        } else if #available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            content.background(.regularMaterial, in: shape)
        }
    }
}

// MARK: - Status

/// What a status message reports, which sets its colour and default icon.
public enum StatusKind: Sendable, Hashable {
    case error, warning, success

    /// The icon shown with the message when the caller doesn't choose one,
    /// so the kind is never conveyed by colour alone.
    public var defaultSystemImage: String {
        switch self {
        case .error: "exclamationmark.octagon"
        case .warning: "exclamationmark.triangle"
        case .success: "checkmark.circle"
        }
    }
}

/// The colour for a status message's text and icon: at least 4.5:1 against
/// the window and grouped-list backgrounds in light and dark appearance, and
/// at least 7:1 when the user has increased contrast.
public struct StatusColors {
    public static func color(_ kind: StatusKind, scheme: ColorScheme, contrast: ColorSchemeContrast) -> Color {
        let rgb = components(kind, dark: scheme == .dark, increased: contrast == .increased)
        return Color(red: rgb.0, green: rgb.1, blue: rgb.2)
    }

    /// sRGB components, 0–1. Kept as numbers so the contrast test can check them.
    public static func components(_ kind: StatusKind, dark: Bool, increased: Bool) -> (Double, Double, Double) {
        switch (kind, dark, increased) {
        case (.error, false, false): (0.698, 0.133, 0.133)   // #B22222
        case (.error, false, true): (0.545, 0.071, 0.071)    // #8B1212
        case (.error, true, false): (1.0, 0.506, 0.478)      // #FF817A
        case (.error, true, true): (1.0, 0.690, 0.667)       // #FFB0AA
        case (.warning, false, false): (0.608, 0.302, 0.0)   // #9B4D00
        case (.warning, false, true): (0.459, 0.224, 0.0)    // #753900
        case (.warning, true, false): (1.0, 0.718, 0.302)    // #FFB74D
        case (.warning, true, true): (1.0, 0.824, 0.553)     // #FFD28D
        case (.success, false, false): (0.106, 0.459, 0.224) // #1B7539
        case (.success, false, true): (0.059, 0.349, 0.157)  // #0F5928
        case (.success, true, false): (0.427, 0.835, 0.549) // #6DD58C
        case (.success, true, true): (0.639, 0.910, 0.714)   // #A3E8B6
        }
    }
}

/// A status message: an icon and text in the status colour, so it is
/// legible (see `StatusColors`) and never conveyed by colour alone.
public struct StatusLabel: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    private let title: String
    private let systemImage: String?
    private let kind: StatusKind

    public init(_ title: String, systemImage: String? = nil, kind: StatusKind) {
        self.title = title
        self.systemImage = systemImage
        self.kind = kind
    }

    public var body: some View {
        Label(title, systemImage: systemImage ?? kind.defaultSystemImage)
            .foregroundStyle(StatusColors.color(kind, scheme: scheme, contrast: contrast))
    }
}

/// Status text without an icon, for a detail line under a `StatusLabel` or
/// under the control it describes.
public struct StatusText: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    private let text: String
    private let kind: StatusKind

    public init(_ text: String, kind: StatusKind) {
        self.text = text
        self.kind = kind
    }

    public var body: some View {
        Text(text).foregroundStyle(StatusColors.color(kind, scheme: scheme, contrast: contrast))
    }
}

// MARK: - Assistive technology

/// Which assistive technologies are running, for behaviour that must change
/// while they are (controls that hide themselves, timed messages).
public struct AssistiveTechnologyState: Sendable, Equatable {
    /// A screen reader (VoiceOver).
    public var screenReader: Bool
    /// Switch Control.
    public var switchControl: Bool

    public init(screenReader: Bool, switchControl: Bool) {
        self.screenReader = screenReader
        self.switchControl = switchControl
    }

    /// Controls must stay on screen and reachable: never hide them on a
    /// timer, and never dismiss a message on a timer. Voice Control and
    /// keyboard navigation can't be detected on every platform, so controls
    /// that do hide must stay reachable by name and by focus while hidden.
    public var keepsControlsVisible: Bool { screenReader || switchControl }
}

public extension EnvironmentValues {
    /// Which assistive technologies are running (see `AssistiveTechnologyState`).
    var assistiveTechnologyState: AssistiveTechnologyState {
        AssistiveTechnologyState(screenReader: accessibilityVoiceOverEnabled,
                                 switchControl: accessibilitySwitchControlEnabled)
    }
}
#endif
