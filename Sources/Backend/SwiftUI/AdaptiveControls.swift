#if canImport(SwiftUI)
import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

// Controls and modifiers named for the behaviour an application wants, so the
// application states it once and each platform provides it its own way. The
// portable backends have the same API
// (Sources/SwiftOpenUI/Compat/AdaptiveControls.swift).

// MARK: - Links and stacks

/// Opens `destination` in the user's default handler (usually the web
/// browser) when activated.
public struct ExternalURLLink<Label: View>: View {
    private let destination: URL
    private let label: () -> Label

    public init(destination: URL, @ViewBuilder label: @escaping () -> Label) {
        self.destination = destination
        self.label = label
    }

    public var body: some View {
        Link(destination: destination, label: label)
    }
}

/// A vertical stack for long content, realizing rows lazily as they scroll
/// into view.
public struct LazyContentStack<Content: View>: View {
    private let alignment: HorizontalAlignment
    private let spacing: CGFloat?
    private let content: () -> Content

    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil,
                @ViewBuilder content: @escaping () -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content
    }

    public var body: some View {
        LazyVStack(alignment: alignment, spacing: spacing ?? 8, content: content)
    }
}

// MARK: - Paged lists

public extension View {
    /// Loads the next page of a long list when its last row appears. Rows
    /// are realized lazily here, so appearing means scrolling into view.
    func loadsNextPageWhenLast(_ isLast: Bool, _ load: @escaping () async -> Void) -> some View {
        onAppear { if isLast { Task { await load() } } }
    }
}

/// An explicit "Load more" control for the next page of a long list, shown
/// where rows are not realized lazily (so `loadsNextPageWhenLast` cannot
/// load on scroll). Rows are lazy here, so it shows nothing.
public struct LoadNextPageButton: View {
    public init(isAvailable: Bool, load: @escaping () -> Void) {}

    public var body: some View {
        EmptyView()
    }
}

// MARK: - Menus

/// One entry of an `AdaptiveActionMenu`.
public struct AdaptiveMenuItem<Value>: Identifiable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let value: Value

    public init(id: String, title: String, systemImage: String, value: Value) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.value = value
    }
}

/// A button showing `systemImage` that opens a menu of `items`; choosing one
/// calls `action` with its value and title. On tvOS this is UIKit's
/// focus-driven button menu, which the remote handles well; elsewhere a
/// SwiftUI `Menu`.
public struct AdaptiveActionMenu<Value>: View {
    private let title: String
    private let systemImage: String
    private let items: [AdaptiveMenuItem<Value>]
    private let action: @MainActor @Sendable (Value, String) -> Void

    public init(title: String, systemImage: String, items: [AdaptiveMenuItem<Value>],
                action: @escaping @MainActor @Sendable (Value, String) -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.items = items
        self.action = action
    }

    public var body: some View {
        #if os(tvOS)
        NativeActionMenuButton(title: title, systemImage: systemImage, items: items, action: action)
        #else
        Menu {
            ForEach(items) { item in
                Button { action(item.value, item.title) } label: {
                    SwiftUI.Label(item.title, systemImage: item.systemImage)
                }
            }
        } label: {
            Image(systemName: systemImage)
        }
        .accessibilityLabel(title)
        #endif
    }
}

#if os(tvOS)
private struct NativeActionMenuButton<Value>: UIViewRepresentable {
    let title: String
    let systemImage: String
    let items: [AdaptiveMenuItem<Value>]
    let action: @MainActor @Sendable (Value, String) -> Void

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: systemImage), for: .normal)
        button.accessibilityLabel = title
        button.showsMenuAsPrimaryAction = true
        button.menu = makeMenu()
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        button.menu = makeMenu()
    }

    private func makeMenu() -> UIMenu {
        UIMenu(title: title, children: items.map { item in
            UIAction(title: item.title, image: UIImage(systemName: item.systemImage)) { _ in
                Task { @MainActor in action(item.value, item.title) }
            }
        })
    }
}
#endif

/// A dialog's standard keyboard shortcut: Return for the default action,
/// Escape for cancel.
public enum DialogShortcut: Sendable, Equatable {
    case defaultAction
    case cancelAction
}

// MARK: - Lists, navigation and text entry

public extension View {
    /// Binds a dialog's standard shortcut (Return for the default action,
    /// Escape for cancel) where the platform has keyboard shortcuts; tvOS has
    /// none (its remote's Menu button already cancels), so there it does
    /// nothing.
    @ViewBuilder
    func keyboardShortcutWhereAvailable(_ shortcut: DialogShortcut) -> some View {
        #if os(tvOS)
        self
        #else
        switch shortcut {
        case .defaultAction: keyboardShortcut(.defaultAction)
        case .cancelAction: keyboardShortcut(.cancelAction)
        }
        #endif
    }

    /// Hides the separator below this list row, where lists draw them
    /// (tvOS lists have none).
    @ViewBuilder
    func hiddenListRowSeparator() -> some View {
        #if os(tvOS)
        self
        #else
        listRowSeparator(.hidden)
        #endif
    }

    /// The title style for a pushed detail page: compact (inline) where
    /// navigation bars offer a large title, on iOS.
    @ViewBuilder
    func detailNavigationStyle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// A destructive action on a list row: a swipe action where rows swipe.
    /// tvOS rows don't swipe, so nothing is added there.
    @ViewBuilder
    func destructiveRowAction(_ title: String, action: @escaping () -> Void) -> some View {
        #if os(tvOS)
        self
        #else
        swipeActions { Button(title, role: .destructive, action: action) }
        #endif
    }

    /// A text field for entering a URL: no automatic capitalization and the
    /// URL keyboard, on iOS's software keyboard.
    @ViewBuilder
    func urlEntryStyle() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never).keyboardType(.URL)
        #else
        self
        #endif
    }

    /// A text field in a settings form: a bordered field where forms draw
    /// them (not tvOS, whose fields are focus targets of their own).
    @ViewBuilder
    func settingsTextEntryStyle() -> some View {
        #if os(tvOS)
        self
        #else
        textFieldStyle(.roundedBorder)
        #endif
    }

    /// Makes read-only text reachable where navigation is by focus alone
    /// (tvOS), so it can be scrolled to and read.
    @ViewBuilder
    func focusableReadOnlyValue() -> some View {
        #if os(tvOS)
        focusable()
        #else
        self
        #endif
    }

    /// A video detail page whose player runs under the navigation bar to the
    /// top edge, on iOS.
    @ViewBuilder
    func immersiveVideoDetailStyle() -> some View {
        #if os(iOS)
        ignoresSafeArea(edges: .top)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }
}

/// Chooses a whole number from `values`, where 0 is shown as `zeroLabel`:
/// a stepper with touch or pointer input, a picker on tvOS, where a
/// remote's focus moves between choices.
public struct RemoteFriendlyBoundedSelection: View {
    private let title: String
    @Binding private var value: Int
    private let values: [Int]
    private let zeroLabel: String
    private let step: Int

    public init(title: String, value: Binding<Int>, values: [Int], zeroLabel: String, step: Int) {
        self.title = title
        _value = value
        self.values = values
        self.zeroLabel = zeroLabel
        self.step = step
    }

    public var body: some View {
        #if os(tvOS)
        Picker(title, selection: $value) {
            Text(zeroLabel).tag(0)
            ForEach(values.filter { $0 != 0 }, id: \.self) { Text(String($0)).tag($0) }
        }
        #else
        Stepper("\(title): \(value == 0 ? zeroLabel.lowercased() : String(value))",
                value: $value, in: (values.min() ?? 0)...(values.max() ?? 0), step: step)
        #endif
    }
}

// MARK: - Settings pages

/// The content of a settings detail page. macOS settings panes scroll from
/// the top at full width; elsewhere the content (usually a `Form`) scrolls
/// itself.
public struct SettingsDetailContainer<Content: View>: View {
    private let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        #if os(macOS)
        ScrollView { content().frame(maxWidth: .infinity) }.defaultScrollAnchor(.top)
        #else
        content()
        #endif
    }
}

// MARK: - Sharing and documents

/// Shares `item` through the system share sheet, or nothing while there is
/// no item or where the platform cannot share (tvOS).
public struct ShareContentAction<Label: View>: View {
    private let item: URL?
    private let label: () -> Label

    public init(item: URL?, @ViewBuilder label: @escaping () -> Label) {
        self.item = item
        self.label = label
    }

    public var body: some View {
        #if os(tvOS)
        EmptyView()
        #else
        if let item { ShareLink(item: item, label: label) }
        #endif
    }
}

/// A settings section that exports a document (once `exportURL` is ready)
/// and asks to import one. Nothing is shown on tvOS, which has no share
/// sheet or file picker.
public struct DocumentTransferControls: View {
    private let title: String
    private let exportURL: URL?
    private let exportLabel: String
    private let importLabel: String
    private let status: String?
    private let requestImport: () -> Void

    public init(title: String, exportURL: URL?, exportLabel: String, importLabel: String,
                status: String?, requestImport: @escaping () -> Void) {
        self.title = title
        self.exportURL = exportURL
        self.exportLabel = exportLabel
        self.importLabel = importLabel
        self.status = status
        self.requestImport = requestImport
    }

    public var body: some View {
        #if os(tvOS)
        EmptyView()
        #else
        Section(title) {
            if let exportURL {
                ShareLink(item: exportURL) { SwiftUI.Label(exportLabel, systemImage: "square.and.arrow.up") }
            } else {
                SwiftUI.Label("Preparing export…", systemImage: "square.and.arrow.up")
                    .foregroundStyle(.secondary)
            }
            Button(action: requestImport) {
                SwiftUI.Label(importLabel, systemImage: "square.and.arrow.down")
            }
            if let status {
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }
        }
        #endif
    }
}

public extension View {
    /// Asks for a JSON document while `isPresented` is true and calls
    /// `onImport` with the chosen file. Nothing is presented on tvOS, which
    /// has no file picker.
    @ViewBuilder
    func jsonDocumentImporter(isPresented: Binding<Bool>, onImport: @escaping (URL) -> Void) -> some View {
        #if os(tvOS)
        self
        #else
        fileImporter(isPresented: isPresented, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            onImport(url)
        }
        #endif
    }

    /// Prepares the document `DocumentTransferControls` exports whenever
    /// `id` changes. Nothing is prepared on tvOS, where nothing can be
    /// exported.
    @ViewBuilder
    func preparesDocumentExport(id: String, _ prepare: @escaping @Sendable () async -> Void) -> some View {
        #if os(tvOS)
        self
        #else
        task(id: id, prepare)
        #endif
    }
}

// MARK: - Full-screen video

public extension View {
    /// Presents `content` (a video player) full screen while `isPresented`
    /// is true, and sets it false when the user leaves full screen.
    ///
    /// - macOS: a dedicated borderless window that enters full screen, so
    ///   the player has no stranded title bar or traffic lights, as in native
    ///   media apps, and dark like them.
    /// - iOS, iPadOS, tvOS, visionOS: nothing; UIKit's player view
    ///   controller presents its own full screen.
    @ViewBuilder
    func videoFullscreenPresentation<Content: View>(
        isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        #if os(macOS)
        modifier(FullscreenWindowPresentation(isPresented: isPresented, content: content))
        #else
        self
        #endif
    }
}

#if os(macOS)
private struct FullscreenWindowPresentation<Presented: View>: ViewModifier {
    @Binding var isPresented: Bool
    let content: () -> Presented
    @State private var presenter = FullscreenWindowPresenter()

    func body(content base: Content) -> some View {
        base
            .onChange(of: isPresented, initial: true) { _, presented in
                if presented {
                    presenter.open(AnyView(content().preferredColorScheme(.dark))) { isPresented = false }
                } else {
                    presenter.close()
                }
            }
            .onDisappear { presenter.close() }
    }
}

/// Owns the full-screen window: opens it in full screen, and closes it once
/// it has left full screen, however that started (the app, the green
/// button, Escape, or closing the window).
private final class FullscreenWindowPresenter: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var onClose: (() -> Void)?

    func open(_ content: AnyView, onClose: @escaping () -> Void) {
        guard window == nil else { return }
        self.onClose = onClose
        let hosting = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.borderless, .resizable]
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        window.collectionBehavior = .fullScreenPrimary
        window.delegate = self
        window.setContentSize(NSSize(width: 1280, height: 720))
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.toggleFullScreen(nil)
        self.window = window
    }

    func close() {
        guard let window else { return }
        if window.styleMask.contains(.fullScreen) {
            // Leave full screen first; windowDidExitFullScreen closes it.
            window.toggleFullScreen(nil)
        } else {
            performClose(window)
        }
    }

    private func performClose(_ window: NSWindow) {
        self.window = nil
        window.delegate = nil
        window.close()
        finish()
    }

    private func finish() {
        let onClose = onClose
        self.onClose = nil
        onClose?()
    }

    nonisolated func windowDidExitFullScreen(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard let window else { return }
            performClose(window)
        }
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            guard window != nil else { return }
            window = nil
            finish()
        }
    }
}
#endif

// MARK: - Diagnostics

/// What has keyboard or remote focus, for debugger output.
public enum FocusDiagnostics {
    /// A description of the focused item where the platform has a focus
    /// engine that reports one (tvOS); nil elsewhere.
    @MainActor
    public static func focusedItemDescription() -> String? {
        #if os(tvOS)
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) else { return "none (no key window)" }
        guard let item = window.windowScene?.focusSystem?.focusedItem else { return "none" }
        let label = (item as? UIView)?.accessibilityLabel ?? ""
        return "\(type(of: item)) \(label)".trimmingCharacters(in: .whitespaces)
        #else
        nil
        #endif
    }
}
#endif

#if canImport(SwiftUI)
/// A titled section the viewer expands and collapses (collapsed at first).
/// A disclosure group where the platform has one; on tvOS, which has none, a
/// button that shows or hides the content. Same API on every backend.
public struct CollapsibleSection<Content: View>: View {
    private let title: String
    private let content: Content
    @State private var expanded = false

    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        #if os(tvOS)
        VStack(alignment: .leading, spacing: 6) {
            Button { expanded.toggle() } label: {
                Label(title, systemImage: expanded ? "chevron.down" : "chevron.right")
            }
            .accessibilityValue(expanded ? "Expanded" : "Collapsed")
            if expanded { content }
        }
        #else
        DisclosureGroup(title, isExpanded: $expanded) { content }
        #endif
    }
}

extension View {
    /// Presents `content` attached to this view: a popover where the platform
    /// has one; on tvOS, which has none, a sheet. Same API on every backend.
    public func attachedPanel<PanelContent: View>(isPresented: Binding<Bool>,
                                                  @ViewBuilder content: @escaping () -> PanelContent) -> some View {
        modifier(AttachedPanel(isPresented: isPresented, panel: content))
    }
}

/// Internal to this module, as `PopoverMenu` is: SwiftUI's popover is emitted
/// into its caller, and a public body calling it, copied into a client by
/// cross-module optimisation, referenced an opaque type descriptor that no
/// module exports (Release link failure).
private struct AttachedPanel<PanelContent: View>: ViewModifier {
    let isPresented: Binding<Bool>
    let panel: () -> PanelContent

    func body(content: Content) -> some View {
        #if os(tvOS)
        content.sheet(isPresented: isPresented, content: panel)
        #else
        content.popover(isPresented: isPresented, content: panel)
        #endif
    }
}
#endif
