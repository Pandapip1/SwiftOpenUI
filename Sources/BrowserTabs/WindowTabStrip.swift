import Foundation
import SwiftOpenUI
#if os(macOS) && !BACKEND_GTK
import AppKit
#endif

public extension View {
    /// The window chrome of a browser-style window, stated once for every
    /// platform:
    ///
    /// - macOS: `historyControls` in the window toolbar, and `tabStrip` as
    ///   window chrome, a row of its own below the toolbar (a titlebar
    ///   accessory), as in Safari and iTerm2.
    /// - visionOS and the portable backends: `historyControls` in the window
    ///   toolbar; their tab chrome is the tab container's own.
    /// - iOS, iPadOS and tvOS: nothing; touch and TV layouts carry both in
    ///   the tab container's bars.
    ///
    /// While `isOverviewPresented`, the tab overview is in front and owns the
    /// chrome, so both are removed. `tabStrip` is hosted outside this view's
    /// hierarchy, so pass it the environment it reads.
    @ViewBuilder
    func browserWindowChrome<Controls: View, Strip: View>(
        isOverviewPresented: Bool,
        @ViewBuilder historyControls: @escaping () -> Controls,
        @ViewBuilder tabStrip: @escaping () -> Strip
    ) -> some View {
        #if os(iOS) || os(tvOS)
        self
        #elseif os(macOS) && !BACKEND_GTK
        self
            .toolbar {
                if !isOverviewPresented {
                    BrowserHistoryToolbar(controls: historyControls)
                }
            }
            .background {
                WindowTabStripInstaller(content: AnyView(tabStrip()), isHidden: isOverviewPresented)
                    .frame(width: 0, height: 0)
            }
        #else
        self
            .toolbar {
                if !isOverviewPresented {
                    BrowserHistoryToolbar(controls: historyControls)
                }
            }
        #endif
    }
}

/// The selected tab's history controls, at the leading edge of the window
/// toolbar.
@MainActor
private struct BrowserHistoryToolbar<Controls: View>: ToolbarContent {
    let controls: () -> Controls

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigation) { controls() }
    }
}

#if os(macOS) && !BACKEND_GTK
final class WindowTabStripAccessoryViewController: NSTitlebarAccessoryViewController {}

/// Owns the tab strip as window chrome. SwiftUI representables can be rebuilt
/// or briefly overlap during navigation, so installation is reconciled at the
/// NSWindow level rather than treating each representable as the accessory's
/// owner.
@MainActor
final class WindowTabStripAccessoryManager: NSObject {
    // BrowserTabBar's label, tab padding, capsule padding, and outer padding
    // require about 37 points at the default macOS font size. Leave one point
    // for pixel rounding rather than clipping the capsule's lower edge.
    static let height: CGFloat = 38

    private weak var window: NSWindow?
    private let accessory = WindowTabStripAccessoryViewController()
    private let hosting: NSHostingController<AnyView>
    private var owners: [UUID: Bool] = [:]

    init(window: NSWindow, content: AnyView) {
        self.window = window
        hosting = NSHostingController(rootView: content)
        super.init()
        accessory.view = hosting.view
        accessory.layoutAttribute = .bottom
        accessory.fullScreenMinHeight = 0
        hosting.view.autoresizingMask = [.width]

        // Selector-based observers are removed by NotificationCenter when the
        // manager is deallocated, so there are no tokens to keep or release.
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(windowDidResize(_:)),
                           name: NSWindow.didResizeNotification, object: window)
        center.addObserver(self, selector: #selector(windowDidChangeFullScreen(_:)),
                           name: NSWindow.didEnterFullScreenNotification, object: window)
        center.addObserver(self, selector: #selector(windowDidChangeFullScreen(_:)),
                           name: NSWindow.didExitFullScreenNotification, object: window)
    }

    var isUnused: Bool { owners.isEmpty }

    func attach(owner: UUID, content: AnyView, isHidden: Bool = false) {
        owners[owner] = isHidden
        hosting.rootView = content
        reconcile()
    }

    func detach(owner: UUID) {
        owners[owner] = nil
        guard owners.isEmpty, let window else { return }
        if let index = window.titlebarAccessoryViewControllers.firstIndex(where: { $0 === accessory }) {
            window.removeTitlebarAccessoryViewController(at: index)
        }
    }

    func reconcile() {
        guard !owners.isEmpty, let window, window.styleMask.contains(.titled) else { return }
        guard owners.values.contains(false) else {
            if let index = window.titlebarAccessoryViewControllers.firstIndex(where: { $0 === accessory }) {
                window.removeTitlebarAccessoryViewController(at: index)
            }
            return
        }
        // Remove abandoned tab-strip accessories left by a replaced SwiftUI
        // coordinator before ensuring this manager's accessory is installed.
        for index in window.titlebarAccessoryViewControllers.indices.reversed() {
            let candidate = window.titlebarAccessoryViewControllers[index]
            if candidate is WindowTabStripAccessoryViewController, candidate !== accessory {
                window.removeTitlebarAccessoryViewController(at: index)
            }
        }
        let width = max(0, window.contentLayoutRect.width)
        hosting.view.frame = NSRect(x: 0, y: 0, width: width, height: Self.height)
        accessory.view.frame = hosting.view.frame
        if !window.titlebarAccessoryViewControllers.contains(where: { $0 === accessory }) {
            window.addTitlebarAccessoryViewController(accessory)
        }
        window.contentView?.needsLayout = true
    }

    @objc private nonisolated func windowDidResize(_ notification: Notification) {
        // Window notifications are posted on the main thread.
        MainActor.assumeIsolated { reconcile() }
    }

    @objc private nonisolated func windowDidChangeFullScreen(_ notification: Notification) {
        // AppKit can report its old content-layout rect until the following
        // main-run-loop turn after a fullscreen transition.
        DispatchQueue.main.async { [weak self] in self?.reconcile() }
    }
}

@MainActor
private final class WindowTabStripAccessoryRegistry {
    static let shared = WindowTabStripAccessoryRegistry()
    private struct Entry { weak var window: NSWindow?; let manager: WindowTabStripAccessoryManager }
    private var entries: [ObjectIdentifier: Entry] = [:]

    func manager(for window: NSWindow, content: AnyView) -> WindowTabStripAccessoryManager {
        purgeReleasedWindows()
        let key = ObjectIdentifier(window)
        if let entry = entries[key], entry.window === window { return entry.manager }
        let manager = WindowTabStripAccessoryManager(window: window, content: content)
        entries[key] = Entry(window: window, manager: manager)
        return manager
    }

    func releaseManager(for window: NSWindow) {
        let key = ObjectIdentifier(window)
        if entries[key]?.manager.isUnused == true { entries[key] = nil }
        purgeReleasedWindows()
    }

    private func purgeReleasedWindows() {
        entries = entries.filter { $0.value.window != nil }
    }
}

/// Mounts the tab strip as a window-managed titlebar accessory of whichever
/// window this view is in.
@MainActor
private struct WindowTabStripInstaller: NSViewRepresentable {
    let content: AnyView
    let isHidden: Bool

    func makeNSView(context: Context) -> WindowObserverView {
        let view = WindowObserverView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: WindowObserverView, context: Context) {
        context.coordinator.content = content
        context.coordinator.isHidden = isHidden
        context.coordinator.move(to: nsView.window)
    }

    func makeCoordinator() -> Coordinator { Coordinator(content: content, isHidden: isHidden) }

    static func dismantleNSView(_ nsView: WindowObserverView, coordinator: Coordinator) {
        coordinator.move(to: nil)
        nsView.coordinator = nil
    }

    @MainActor
    final class Coordinator {
        var content: AnyView
        var isHidden: Bool
        private let owner = UUID()
        private weak var installedWindow: NSWindow?

        init(content: AnyView, isHidden: Bool) {
            self.content = content
            self.isHidden = isHidden
        }

        func move(to window: NSWindow?) {
            if installedWindow !== window, let old = installedWindow {
                let registry = WindowTabStripAccessoryRegistry.shared
                let manager = registry.manager(for: old, content: content)
                manager.detach(owner: owner)
                registry.releaseManager(for: old)
            }
            guard let window else { installedWindow = nil; return }
            let manager = WindowTabStripAccessoryRegistry.shared.manager(for: window, content: content)
            manager.attach(owner: owner, content: content, isHidden: isHidden)
            installedWindow = window
        }
    }

    @MainActor
    final class WindowObserverView: NSView {
        weak var coordinator: Coordinator?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            coordinator?.move(to: window)
        }
    }
}
#endif
