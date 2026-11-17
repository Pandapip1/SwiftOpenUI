#if canImport(SwiftUI)
import Combine
import SwiftUI
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Where the scene (window) showing a view is in its life.
public enum LifecyclePhase: Sendable, Hashable {
    /// In front, taking input.
    case active
    /// Visible but not taking input (another window or app is in front).
    case inactive
    /// Not visible: backgrounded (iOS), or its window hidden.
    case background
}

/// Something that happened to the scene showing a view, or to the
/// application. Same API on every backend; see `View.onLifecycle`.
public enum LifecycleEvent: Sendable, Hashable {
    /// The scene's phase changed.
    case phase(LifecyclePhase)
    /// The application is about to quit. Work must finish before the
    /// action returns.
    case willTerminate
    /// The scene (window) is going away for good: closed, or its scene
    /// discarded. Delivered once, before its views are torn down, and not
    /// for hiding, minimising or backgrounding.
    case sceneEnded
}

public extension View {
    /// Calls `action` with the lifecycle events of the scene (window) that
    /// shows this view, and with application termination.
    ///
    /// - Phase: SwiftUI's scene phase.
    /// - Termination: the application's will-terminate notification.
    /// - Scene end: AppKit's window-will-close for the hosting window on
    ///   macOS; UIKit's scene disconnect for the hosting scene on iOS,
    ///   iPadOS, tvOS and visionOS.
    func onLifecycle(perform action: @escaping @MainActor (LifecycleEvent) -> Void) -> some View {
        modifier(LifecycleModifier(action: action))
    }

    /// Calls `action` once, when the scene (window) showing this view goes
    /// away for good or the application quits, whichever comes first: the
    /// place to stop what the window owns (playback, audio, timers).
    func onSceneEnd(perform action: @escaping @MainActor () -> Void) -> some View {
        modifier(SceneEndModifier(action: action))
    }
}

private struct LifecycleModifier: ViewModifier {
    let action: @MainActor (LifecycleEvent) -> Void
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active: action(.phase(.active))
                case .inactive: action(.phase(.inactive))
                case .background: action(.phase(.background))
                @unknown default: break
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: willTerminateNotification)) { _ in
                action(.willTerminate)
            }
            .background(SceneEndProbe { action(.sceneEnded) })
    }
}

private struct SceneEndModifier: ViewModifier {
    let action: @MainActor () -> Void
    @State private var fired = FiredFlag()

    func body(content: Content) -> some View {
        let fired = fired
        let action = action
        return content.onLifecycle { event in
            guard event == .sceneEnded || event == .willTerminate, !fired.value else { return }
            fired.value = true
            action()
        }
    }
}

@MainActor
private final class FiredFlag {
    var value = false
}

@MainActor
private var willTerminateNotification: Notification.Name {
    #if os(macOS)
    NSApplication.willTerminateNotification
    #else
    UIApplication.willTerminateNotification
    #endif
}

/// Watches the window (macOS) or scene (UIKit) that hosts it and calls
/// `onEnd` once when it closes or disconnects, before its views go.
@MainActor
private final class SceneEndCoordinator {
    var onEnd: @MainActor () -> Void
    private var observer: NSObjectProtocol?
    private var ended = false

    init(onEnd: @escaping @MainActor () -> Void) { self.onEnd = onEnd }

    func watch(_ name: Notification.Name, object: AnyObject?) {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        guard let object, !ended else { return }
        observer = NotificationCenter.default.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    private func end() {
        guard !ended else { return }
        ended = true
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        onEnd()
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }
}

#if os(macOS)
private struct SceneEndProbe: NSViewRepresentable {
    let onEnd: @MainActor () -> Void

    func makeCoordinator() -> SceneEndCoordinator { SceneEndCoordinator(onEnd: onEnd) }

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ view: ProbeView, context: Context) {
        context.coordinator.onEnd = onEnd
    }

    static func dismantleNSView(_ view: ProbeView, coordinator: SceneEndCoordinator) {
        coordinator.stop()
    }

    final class ProbeView: NSView {
        weak var coordinator: SceneEndCoordinator?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            coordinator?.watch(NSWindow.willCloseNotification, object: window)
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
#elseif canImport(UIKit)
private struct SceneEndProbe: UIViewRepresentable {
    let onEnd: @MainActor () -> Void

    func makeCoordinator() -> SceneEndCoordinator { SceneEndCoordinator(onEnd: onEnd) }

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: ProbeView, context: Context) {
        context.coordinator.onEnd = onEnd
    }

    static func dismantleUIView(_ view: ProbeView, coordinator: SceneEndCoordinator) {
        coordinator.stop()
    }

    final class ProbeView: UIView {
        weak var coordinator: SceneEndCoordinator?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            coordinator?.watch(UIScene.didDisconnectNotification, object: window?.windowScene)
        }
    }
}
#endif
#endif
