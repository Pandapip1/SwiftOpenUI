import Foundation

import SwiftOpenUI
#if !BACKEND_GTK
import Observation
#endif
#if !BACKEND_GTK && !os(tvOS)
import UniformTypeIdentifiers
#endif
#if BACKEND_GTK
@_spi(SwiftOpenUIBackend) import BackendGTK4
import CGTK
import CAdwaita
#endif

public struct BrowserTabItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let isPinned: Bool
    /// A symbol shown beside the tab's title, such as its section's icon.
    public let systemImage: String?

    public init(id: UUID, title: String, isPinned: Bool = false, systemImage: String? = nil) {
        self.id = id
        self.title = title
        self.isPinned = isPinned
        self.systemImage = systemImage
    }
}

/// A tab container's keyboard commands, the same on every backend: ⌘W closes
/// the selected tab, ⌘T opens a new one, ⌘⇧T reopens the last tab closed,
/// ⌘1–⌘8 select a tab by position and ⌘9 the last, and ⌃Tab / ⌃⇧Tab show
/// the next and previous tabs. (⌘ is Ctrl on GTK.)
public extension View {
    /// ⌘T for the app's new-tab control (the tab chrome's + button), so the
    /// shortcut does exactly what the button does. Not on focus-only
    /// platforms such as tvOS. A container given `onNewTab` offers ⌘T as a
    /// command instead.
    @ViewBuilder
    func browserNewTabKeyboardShortcut() -> some View {
        #if os(tvOS)
        self
        #else
        keyboardShortcut("t")
        #endif
    }
}

enum BrowserTabShortcut: Equatable {
    case closeTab, newTab, reopenClosedTab, nextTab, previousTab
    case selectTab(Int)

    static var all: [BrowserTabShortcut] {
        [.closeTab, .newTab, .reopenClosedTab, .nextTab, .previousTab] + (1...9).map { .selectTab($0) }
    }

    var key: KeyEquivalent {
        switch self {
        case .closeTab: "w"
        case .newTab, .reopenClosedTab: "t"
        case .nextTab, .previousTab: .tab
        case .selectTab(let number): KeyEquivalent(Character(String(number)))
        }
    }

    var modifiers: EventModifiers {
        switch self {
        case .closeTab, .newTab, .selectTab: .command
        case .reopenClosedTab: [.command, .shift]
        case .nextTab: .control
        case .previousTab: [.control, .shift]
        }
    }

    var title: String {
        switch self {
        case .closeTab: "Close Tab"
        case .newTab: "New Tab"
        case .reopenClosedTab: "Reopen Closed Tab"
        case .nextTab: "Show Next Tab"
        case .previousTab: "Show Previous Tab"
        case .selectTab(9): "Show Last Tab"
        case .selectTab(let number): "Show Tab \(number)"
        }
    }
}

/// What the tab commands act on: one tab container's tabs and actions.
struct BrowserTabCommandTarget {
    let items: [BrowserTabItem]
    let selection: Binding<UUID>
    let onClose: (UUID) -> Void
    let onNewTab: (() -> Void)?
    let onReopenClosedTab: (() -> Void)?

    func isEnabled(_ shortcut: BrowserTabShortcut) -> Bool {
        switch shortcut {
        case .closeTab: items.contains { $0.id == selection.wrappedValue && !$0.isPinned }
        case .newTab: onNewTab != nil
        case .reopenClosedTab: onReopenClosedTab != nil
        case .nextTab, .previousTab: items.count > 1
        case .selectTab(let number): number == 9 ? !items.isEmpty : items.indices.contains(number - 1)
        }
    }

    func perform(_ shortcut: BrowserTabShortcut) {
        guard isEnabled(shortcut) else { return }
        switch shortcut {
        case .closeTab: onClose(selection.wrappedValue)
        case .newTab: onNewTab?()
        case .reopenClosedTab: onReopenClosedTab?()
        case .nextTab, .previousTab:
            guard let index = items.firstIndex(where: { $0.id == selection.wrappedValue }) else { return }
            let offset = shortcut == .nextTab ? 1 : -1
            selection.wrappedValue = items[(index + offset + items.count) % items.count].id
        case .selectTab(let number):
            let item = number == 9 ? items[items.count - 1] : items[number - 1]
            selection.wrappedValue = item.id
        }
    }
}


/// Where a tab strip puts each tab, as the system's window tabs do: the tabs
/// share the width equally down to a minimum width. Beyond that the strip
/// scrolls a tab at a time: it shows a run of whole tabs, and the tabs
/// scrolled off each end are thin slivers stacked at that edge, never tabs
/// cut off mid-title.
struct BrowserTabStripLayout: Equatable {
    static let minimumTabWidth: CGFloat = 120
    static let sliverWidth: CGFloat = 5
    /// Slivers drawn at each edge; any more lie under them.
    static let maximumSlivers = 4
    /// The width of each edge's sliver area while the strip overflows.
    static var edgeWidth: CGFloat { CGFloat(maximumSlivers) * sliverWidth }

    enum Slot: Equatable {
        /// A whole tab.
        case tab(x: CGFloat, width: CGFloat)
        /// A tab scrolled off an edge.
        case sliver(x: CGFloat)
    }

    let count: Int
    /// The first whole tab.
    let first: Int
    /// How many tabs are whole.
    let shown: Int
    let tabWidth: CGFloat

    var isOverflowing: Bool { shown < count }
    /// The first tabs that can be shown first: from no tab scrolled off to
    /// the last tab at the trailing end.
    var firstRange: ClosedRange<Int> { 0...max(0, count - shown) }

    /// `count` tabs in `width`, scrolled to show tab `first` first where the
    /// tabs overflow (clamped to what can be shown).
    init(count: Int, width: CGFloat, first: Int) {
        self.count = count
        let width = max(0, width)
        if count <= max(1, Int(width / Self.minimumTabWidth)) {
            shown = count
            self.first = 0
            tabWidth = count > 0 ? width / CGFloat(count) : width
        } else {
            let available = max(0, width - 2 * Self.edgeWidth)
            shown = max(1, Int(available / Self.minimumTabWidth))
            self.first = min(max(0, first), count - shown)
            tabWidth = available / CGFloat(shown)
        }
    }

    /// The first tab to show so that tab `index` is whole, scrolling as
    /// little as possible.
    func first(revealing index: Int) -> Int {
        guard index >= 0, index < count else { return first }
        if index < first { return index }
        if index >= first + shown { return index - shown + 1 }
        return first
    }

    func slot(of index: Int) -> Slot {
        guard isOverflowing else { return .tab(x: CGFloat(index) * tabWidth, width: tabWidth) }
        let edge = Self.edgeWidth, end = first + shown
        if index < first {
            // Nearest the whole tabs first; the rest stack under the last.
            let depth = min(first - index, Self.maximumSlivers)
            return .sliver(x: edge - CGFloat(depth) * Self.sliverWidth)
        }
        if index >= end {
            let depth = min(index - end, Self.maximumSlivers - 1)
            return .sliver(x: edge + CGFloat(shown) * tabWidth + CGFloat(depth) * Self.sliverWidth)
        }
        return .tab(x: edge + CGFloat(index - first) * tabWidth, width: tabWidth)
    }
}

#if !BACKEND_GTK
public struct BrowserHistoryControls: View {
    private let canGoBack: () -> Bool
    private let canGoForward: () -> Bool
    private let goBack: () -> Void
    private let goForward: () -> Void

    public init(canGoBack: @autoclosure @escaping () -> Bool,
                canGoForward: @autoclosure @escaping () -> Bool,
                goBack: @escaping () -> Void, goForward: @escaping () -> Void) {
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.goBack = goBack
        self.goForward = goForward
    }

    public var body: some View {
        ControlGroup {
            Button(action: goBack) { Image(systemName: "chevron.left") }
                .disabled(!canGoBack()).accessibilityLabel("Back")
            Button(action: goForward) { Image(systemName: "chevron.right") }
                .disabled(!canGoForward()).accessibilityLabel("Forward")
        }
        .modifier(BrowserNavigationControlGroupStyle())
    }
}
#endif

private struct BrowserTabToolbarActiveKey: EnvironmentKey {
    static let defaultValue = true
}

private struct BrowserTabVisibleKey: EnvironmentKey {
    static let defaultValue = true
}

/// The tab container's per-page state. Internal on purpose: pages react to it
/// only through this module's modifiers (`browserPageToolbarItem`,
/// `browserPageSearchField`, `browserTaskOnceVisible`,
/// `browserTaskWhileVisible`), which never change a page's own structure. A
/// page that branched on these values itself would be rebuilt, losing its
/// state, every time its tab was switched to or from.
extension EnvironmentValues {
    /// True only for the selected tab while the normal browser view is shown.
    var isBrowserTabToolbarActive: Bool {
        get { self[BrowserTabToolbarActiveKey.self] }
        set { self[BrowserTabToolbarActiveKey.self] = newValue }
    }

    /// True while the page is on screen: its tab is selected, or the overview
    /// shows its card.
    var isBrowserTabVisible: Bool {
        get { self[BrowserTabVisibleKey.self] }
        set { self[BrowserTabVisibleKey.self] = newValue }
    }
}

#if !BACKEND_GTK
public enum BrowserTabToolbarPlacement: Sendable {
    case leading, principal, trailing
}

public extension View {
    /// An action belonging to a page, in the page's own toolbar: its
    /// navigation bar, or on macOS the window toolbar while its tab is the
    /// active one. The tab chrome never carries page actions.
    ///
    /// Apply it inside the page's `NavigationStack`. Inactive tabs stay
    /// mounted, so the item is only contributed while
    /// `isBrowserTabToolbarActive` is true. On tvOS pages expose actions
    /// through focusable toolbar content instead, so nothing is added.
    func browserPageToolbarItem<Item: View>(
        id: String, placement: BrowserTabToolbarPlacement,
        @ViewBuilder content: @escaping () -> Item
    ) -> some View {
        modifier(BrowserPageToolbarItem(placement: placement, item: content))
    }
}

private struct BrowserPageToolbarItem<Item: View>: ViewModifier {
    @Environment(\.isBrowserTabToolbarActive) private var isActive
    let placement: BrowserTabToolbarPlacement
    let item: () -> Item

    func body(content: Content) -> some View {
        content.toolbar {
            if isActive {
                ToolbarItem(placement: toolbarPlacement) { item() }
            }
        }
    }

    private var toolbarPlacement: ToolbarItemPlacement {
        switch placement {
        #if os(iOS)
        case .leading: .topBarLeading
        case .trailing: .topBarTrailing
        #elseif os(tvOS)
        case .leading: .automatic
        case .trailing: .primaryAction
        #else
        case .leading: .navigation
        case .trailing: .primaryAction
        #endif
        case .principal: .principal
        }
    }
}

public extension View {
    /// The page's search field, in the page's own chrome, for as long as the
    /// page exists. It never changes the page's structure (so switching tabs
    /// doesn't rebuild the page): pages with their own navigation bar keep a
    /// native search field there; on macOS, where all tabs share the window
    /// toolbar, the field is a native search field in the toolbar while the
    /// page's tab is the active one. Return calls `onSubmit`.
    func browserPageSearchField(text: Binding<String>, prompt: String,
                                onSubmit: @escaping () -> Void) -> some View {
        modifier(BrowserPageSearchField(text: text, prompt: prompt, onSubmit: onSubmit))
    }

    /// Runs `action` for `id` once the page is first on screen, instead of in
    /// every background tab (tabs stay mounted). Hiding the page doesn't
    /// cancel finished work; it runs again only when `id` changes, or if it
    /// was cancelled before finishing.
    func browserTaskOnceVisible<ID: Equatable & Sendable>(
        id: ID, _ action: @escaping @MainActor () async -> Void
    ) -> some View {
        modifier(BrowserOnceVisibleTask(id: id, action: action))
    }

    /// Runs `action` whenever the page comes on screen and cancels it when the
    /// page goes off screen, for work only worth doing while the page can be
    /// seen, such as watching for changes.
    func browserTaskWhileVisible(_ action: @escaping @MainActor () async -> Void) -> some View {
        modifier(BrowserWhileVisibleTask(action: action))
    }
}

private struct BrowserPageSearchField: ViewModifier {
    @Environment(\.isBrowserTabToolbarActive) private var isActive
    @Binding var text: String
    let prompt: String
    let onSubmit: () -> Void

    func body(content: Content) -> some View {
        #if os(macOS)
        content.toolbar {
            if isActive {
                ToolbarItem(placement: .principal) {
                    BrowserToolbarSearchField(text: $text, prompt: prompt, onSubmit: onSubmit)
                        .frame(minWidth: 220, idealWidth: 380, maxWidth: 520)
                }
            }
        }
        #else
        content
            .searchable(text: $text, prompt: prompt)
            .onSubmit(of: .search, onSubmit)
        #endif
    }
}

#if os(macOS)
/// A native search field for the window toolbar: Return submits, and the
/// field draws its own focus ring and insets.
private struct BrowserToolbarSearchField: NSViewRepresentable {
    @Binding var text: String
    let prompt: String
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, onSubmit: onSubmit) }

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.sendsWholeSearchString = true
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit(_:))
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = prompt
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            text.wrappedValue = field.stringValue
        }

        @objc func submit(_ sender: NSSearchField) {
            text.wrappedValue = sender.stringValue
            guard !sender.stringValue.isEmpty else { return }
            onSubmit()
        }
    }
}
#endif

/// Starts the work for `id` the first time the page is visible and then lets
/// it finish even if the page is hidden meanwhile (switching tabs away from a
/// loading page must not cancel the load, which the page would then show as
/// a failure when it comes back). It is cancelled only when `id` changes or
/// the page goes away for good.
private struct BrowserOnceVisibleTask<ID: Equatable & Sendable>: ViewModifier {
    @Environment(\.isBrowserTabVisible) private var isVisible
    let id: ID
    let action: @MainActor () async -> Void
    @State private var started: BrowserStartedTask<ID>?

    func body(content: Content) -> some View {
        content
            .onAppear(perform: startIfNeeded)
            .onChange(of: BrowserVisibleTaskKey(id: id, isVisible: isVisible), startIfNeeded)
            .onDisappear {
                started?.task.cancel()
                started = nil
            }
    }

    private func startIfNeeded() {
        guard isVisible, started?.id != id else { return }
        started?.task.cancel()
        let action = action
        started = BrowserStartedTask(id: id, task: Task { await action() })
    }
}

private struct BrowserStartedTask<ID: Equatable & Sendable> {
    let id: ID
    let task: Task<Void, Never>
}

private struct BrowserVisibleTaskKey<ID: Equatable & Sendable>: Equatable, Sendable {
    let id: ID
    let isVisible: Bool
}

private struct BrowserWhileVisibleTask: ViewModifier {
    @Environment(\.isBrowserTabVisible) private var isVisible
    let action: @MainActor () async -> Void

    func body(content: Content) -> some View {
        content.task(id: isVisible) {
            guard isVisible else { return }
            await action()
        }
    }
}

/// A set of tabs, each holding one page. Every page is mounted once and stays
/// mounted (state, playback, web views and scroll positions are kept); the
/// container normally shows exactly one of them, the selected tab's, and the
/// others are present but invisible. The overview is the exception: the same
/// pages are all shown at once, each scaled into its card. No page is ever
/// rendered a second time.
public struct BrowserTabContainer<Content: View>: View {
    public let items: [BrowserTabItem]
    public let selection: Binding<UUID>
    public let onClose: (UUID) -> Void
    /// Moves a tab to an index among all tabs, from the overview. `nil`
    /// leaves the overview without reordering.
    public let onMove: ((UUID, Int) -> Void)?
    private let newTabControl: AnyView?
    private let onNewTab: (() -> Void)?
    /// Reopens the tab closed last; `nil` when there is none.
    private let onReopenClosedTab: (() -> Void)?
    private let content: (BrowserTabItem) -> Content
    private let overviewPresented: Binding<Bool>?
    @State private var showingOverview = false
    /// False until the first frame is up: launch builds only the selected
    /// tab's page, and the others are mounted right after, once (they then
    /// stay mounted like every page). A launch with many restored tabs would
    /// otherwise build all their pages before anything appears.
    @State private var mountsEveryPage = false
    @Environment(\.browserTabControls) private var tabControls

    public init(items: [BrowserTabItem], selection: Binding<UUID>, onClose: @escaping (UUID) -> Void,
                onMove: ((UUID, Int) -> Void)? = nil,
                overviewPresented: Binding<Bool>? = nil, onNewTab: (() -> Void)? = nil,
                onReopenClosedTab: (() -> Void)? = nil,
                @ViewBuilder content: @escaping (BrowserTabItem) -> Content) {
        self.items = items
        self.selection = selection
        self.onClose = onClose
        self.onMove = onMove
        self.newTabControl = nil
        self.onNewTab = onNewTab
        self.onReopenClosedTab = onReopenClosedTab
        self.overviewPresented = overviewPresented
        self.content = content
    }

    public init<NewTabControl: View>(
        items: [BrowserTabItem], selection: Binding<UUID>, onClose: @escaping (UUID) -> Void,
        onMove: ((UUID, Int) -> Void)? = nil,
        overviewPresented: Binding<Bool>? = nil, onNewTab: (() -> Void)? = nil,
        onReopenClosedTab: (() -> Void)? = nil,
        @ViewBuilder newTabControl: () -> NewTabControl,
        @ViewBuilder content: @escaping (BrowserTabItem) -> Content
    ) {
        self.items = items
        self.selection = selection
        self.onClose = onClose
        self.onMove = onMove
        self.newTabControl = AnyView(newTabControl())
        self.onNewTab = onNewTab
        self.onReopenClosedTab = onReopenClosedTab
        self.overviewPresented = overviewPresented
        self.content = content
    }

    private var isShowingOverview: Bool {
        get { overviewPresented?.wrappedValue ?? showingOverview }
        nonmutating set {
            if let overviewPresented { overviewPresented.wrappedValue = newValue }
            else { showingOverview = newValue }
        }
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                if isShowingOverview {
                    BrowserTabOverview(items: items, selection: selection, onClose: onClose, onMove: onMove,
                                       newTabControl: newTabControl, pageSize: geometry.size,
                                       select: select, dismiss: { isShowingOverview = false })
                        .transition(.opacity)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            // The pages are always this same layer, in every mode, so changing
            // mode never mounts a page again. In the overview each card reports
            // where its page goes.
            .overlayPreferenceValue(BrowserTabOverviewLayout.self) { layout in
                pages(size: geometry.size, layout: isShowingOverview ? layout : .init())
            }
        }
        .modifier(BrowserTabControlsPlacement(controls: barControls))
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: isShowingOverview)
        #if !os(iOS) && !os(tvOS)
        .toolbar { overviewToolbar }
        #endif
        .modifier(BrowserTabCommandsTarget(target: BrowserTabCommandTarget(
            items: items, selection: selection, onClose: onClose,
            onNewTab: onNewTab, onReopenClosedTab: onReopenClosedTab)))
    }

    /// Every tab's page, laid out once at the size of the tab area. A page
    /// with a card is moved and scaled into it, which costs no layout. The
    /// selected page animates between its card and the whole area (the zoom);
    /// the others change without animation, and while invisible drive none.
    private func pages(size: CGSize, layout: BrowserTabOverviewLayout.Value) -> some View {
        GeometryReader { proxy in
            let area = CGRect(origin: .zero, size: size)
            // In the overview, pages are cut off outside its scrolling area.
            let visible = layout.viewport.map { proxy[$0] } ?? area
            ZStack(alignment: .topLeading) {
                ForEach(items) { item in
                    let isSelected = selection.wrappedValue == item.id
                    let card = layout.cards[item.id].map { proxy[$0] }
                    let frame = card ?? area
                    // A card's page is laid out at the tab's real size and scaled to fill
                    // the card, cropped from the top leading corner.
                    let scale = card.map { card in
                        max(card.width / max(area.width, 1), card.height / max(area.height, 1))
                    } ?? 1
                    let isInteractive = isSelected && !isShowingOverview
                    if mountsEveryPage || isSelected {
                    content(item)
                        .frame(width: area.width, height: area.height)
                        .clipShape(BrowserTabPageClip(
                            cornerRadius: card.map { _ in BrowserTabOverviewCard.cornerRadius / max(scale, 0.01) },
                            size: card.map { CGSize(width: $0.width / max(scale, 0.01), height: $0.height / max(scale, 0.01)) }))
                        .scaleEffect(scale, anchor: .topLeading)
                        .offset(x: frame.minX, y: frame.minY)
                        // A card's page fades with its card as it is swiped off or dragged.
                        .opacity(card != nil ? layout.opacities[item.id, default: 1] : isInteractive ? 1 : 0)
                        .transaction { transaction in
                            if !isSelected {
                                transaction.animation = nil
                                transaction.disablesAnimations = true
                            }
                        }
                        .allowsHitTesting(isInteractive)
                        .accessibilityHidden(!isInteractive)
                        // Nor can keyboard or remote focus enter a page that isn't in
                        // use (invisible, or drawn in a card, whose own control has focus).
                        .modifier(BrowserTabPageFocus(isInteractive: isInteractive, isInCard: card != nil))
                        // Embedded native surfaces such as WKWebView keep their own
                        // backing view; promote the selected page so insertion
                        // order cannot leave an inactive surface above it.
                        .zIndex(isSelected ? 1 : 0)
                        .environment(\.isBrowserTabToolbarActive, isInteractive)
                        .environment(\.isBrowserTabVisible, card != nil || isInteractive)
                    }
                }
                // Each card's close button, over its page's top-trailing corner.
                ForEach(items.filter { !$0.isPinned }) { item in
                    if let card = layout.cards[item.id].map({ proxy[$0] }) {
                        BrowserTabCardCloseButton(title: item.title) { onClose(item.id) }
                            .position(x: card.maxX - 18, y: card.minY + 18)
                            .opacity(layout.opacities[item.id, default: 1])
                            .zIndex(2)
                    }
                }
            }
            .frame(width: area.width, height: area.height, alignment: .topLeading)
            .task {
                // After the first frame (the selected page alone), mount the
                // rest without animation.
                guard !mountsEveryPage else { return }
                try? await Task.sleep(for: .milliseconds(50))
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { mountsEveryPage = true }
            }
            .mask(alignment: .topLeading) {
                BrowserTabPageClip(cornerRadius: nil, bounds: layout.viewport == nil ? nil : visible)
            }
        }
    }

    #if !os(iOS) && !os(tvOS)
    @ToolbarContentBuilder
    private var overviewToolbar: some ToolbarContent {
        // Tab controls only. Pages put their own actions in their own
        // toolbars; the tab chrome never carries them. The overview has its
        // own bar with these controls, so they aren't shown twice. Where the
        // container has a bar of its own (iOS, tvOS), the controls are there
        // instead (`barControls`), never in a toolbar as well.
        if !isShowingOverview {
            ToolbarItem(placement: .primaryAction) {
                #if os(macOS)
                // The window's tab strip (BrowserTabBar) has the new-tab control
                // at its end, as the system's window tabs do.
                overviewButton
                #else
                tabManagementControl
                #endif
            }
        }
    }
    #endif

    /// The controls for the container's own bar: the app's, or by default
    /// the new-tab control and the overview button.
    private var barControls: AnyView? {
        guard !isShowingOverview else { return nil }
        return tabControls ?? AnyView(tabManagementControl)
    }

    private var tabManagementControl: some View {
        ControlGroup {
            if let newTabControl {
                newTabControl
            }
            overviewButton
        }
        .modifier(BrowserNavigationControlGroupStyle())
    }

    private var overviewButton: some View {
        Button { isShowingOverview.toggle() } label: { Image(systemName: "square.on.square") }
            .accessibilityLabel(isShowingOverview ? "Close Tab Overview" : "Tab Overview")
    }

    private func select(_ id: UUID) {
        selection.wrappedValue = id
        isShowingOverview = false
    }
}

private struct BrowserTabCommandTargetKey: FocusedValueKey {
    typealias Value = BrowserTabCommandTarget
}

extension FocusedValues {
    /// The tab container of the focused window, for the tab commands.
    var browserTabCommandTarget: BrowserTabCommandTarget? {
        get { self[BrowserTabCommandTargetKey.self] }
        set { self[BrowserTabCommandTargetKey.self] = newValue }
    }
}

/// Offers a container's tabs to the tab commands while its window is focused.
private struct BrowserTabCommandsTarget: ViewModifier {
    let target: BrowserTabCommandTarget

    func body(content: Content) -> some View {
        #if os(tvOS)
        content
        #else
        content.focusedSceneValue(\.browserTabCommandTarget, target)
        #endif
    }
}

public extension Scene {
    /// Adds the tab containers' keyboard commands (``BrowserTabShortcut``) to
    /// the app's menus, acting on the focused window's tabs. ⌘W closes the
    /// selected tab; with only one tab left it closes the window, as in
    /// Safari, where windows can be closed (on iOS the tab is closed, as a
    /// scene there is not closed from the keyboard).
    func browserTabCommands() -> some Scene {
        #if os(tvOS)
        self
        #else
        commands { BrowserTabCommands() }
        #endif
    }
}

#if !os(tvOS)
private struct BrowserTabCommands: Commands {
    @FocusedValue(\.browserTabCommandTarget) private var target

    var body: some Commands {
        CommandGroup(replacing: .saveItem) {
            #if os(macOS)
            if let target, target.items.count > 1 {
                command(.closeTab, target)
                Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
            } else {
                // The last tab closes with its window.
                Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                    .keyboardShortcut("w")
            }
            #else
            command(.closeTab, target)
            #endif
        }
        CommandGroup(after: .newItem) {
            // Without `onNewTab`, ⌘T belongs to the app's own new-tab control.
            if target?.onNewTab != nil {
                command(.newTab, target)
            }
            command(.reopenClosedTab, target)
        }
        #if os(macOS)
        CommandGroup(before: .windowList) { tabSelection }
        #else
        // iPadOS has no window-list group; the same commands get their own menu.
        CommandMenu("Tabs") { tabSelection }
        #endif
    }

    @ViewBuilder private var tabSelection: some View {
        command(.previousTab, target)
        command(.nextTab, target)
        Divider()
        ForEach(1...9, id: \.self) { number in
            command(.selectTab(number), target)
        }
        Divider()
    }

    private func command(_ shortcut: BrowserTabShortcut, _ target: BrowserTabCommandTarget?) -> some View {
        Button(shortcut.title) { target?.perform(shortcut) }
            .keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
            .disabled(!(target?.isEnabled(shortcut) ?? false))
    }
}
#endif

private struct BrowserTabControlsKey: EnvironmentKey {
    static var defaultValue: AnyView? { nil }
}

extension EnvironmentValues {
    var browserTabControls: AnyView? {
        get { self[BrowserTabControlsKey.self] }
        set { self[BrowserTabControlsKey.self] = newValue }
    }
}

public extension View {
    /// The tab system's own controls for the selected tab (history, the
    /// section or new-tab menu, the overview button), for the tab containers
    /// below. The container places them in its own bar, outside every page:
    /// along the bottom on iOS and the top on tvOS. On macOS the window's tab
    /// strip carries these controls, so the container adds no bar there. The
    /// bar is hidden while the overview is shown.
    func browserTabControls<Controls: View>(@ViewBuilder _ controls: () -> Controls) -> some View {
        environment(\.browserTabControls, AnyView(controls()))
    }
}

/// Puts the tab controls in the container's bar, where this platform has one.
/// The bar takes its space from the tab area: pages are laid out in what is
/// left, so the bar never covers a page (a list's last row ends where the
/// bar begins), and the area grows back when the bar goes away. The bar's
/// own background may extend into the safe area beyond it.
private struct BrowserTabControlsPlacement: ViewModifier {
    let controls: AnyView?

    func body(content: Content) -> some View {
        #if os(iOS)
        VStack(spacing: 0) {
            content
            if let controls {
                // A floating bar of glass, as Safari's.
                controls
                    .modifier(BrowserTabGlass(shape: Capsule()))
                    .padding(.horizontal)
                    .padding(.vertical, 4)
            }
        }
        #elseif os(tvOS)
        VStack(spacing: 0) {
            if let controls {
                controls
                    .modifier(BrowserTabGlass(shape: Capsule()))
                    .padding(.horizontal)
                    .padding(.vertical, 4)
            }
            content
        }
        #else
        content
        #endif
    }
}

/// Where a page may draw. Outside the overview this clips nothing, so pages
/// keep drawing into the safe areas (bars under the status bar and home
/// indicator); in a card it rounds the page's lower corners, and the pages
/// layer is cut off at the overview's scrolling area.
/// Fades a card and tells the pages layer, so its page (drawn there, not in
/// the card) fades with it.
private struct BrowserTabCardOpacity: ViewModifier {
    let id: UUID
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .transformPreference(BrowserTabOverviewLayout.self) { layout in
                layout.opacities[id, default: 1] *= opacity
            }
    }
}

/// Keeps keyboard and remote focus out of a page that isn't in use: one that
/// is invisible, or (on tvOS, where focus moves between the overview's
/// cards) one drawn in a card. Elsewhere a card's page keeps its live
/// appearance, and hit testing already keeps pointers out of it.
private struct BrowserTabPageFocus: ViewModifier {
    let isInteractive: Bool
    let isInCard: Bool

    func body(content: Content) -> some View {
        #if os(tvOS)
        content.disabled(!isInteractive)
        #else
        content.disabled(!isInteractive && !isInCard)
        #endif
    }
}

private struct BrowserTabPageClip: Shape {
    /// The corner radius, when the page is in a card.
    var cornerRadius: CGFloat?
    /// The area to keep, in the shape's own coordinates; `nil` for all of it.
    var bounds: CGRect?
    /// In a card, the part of the page the card shows, from its top leading
    /// corner; `nil` for all of it.
    var size: CGSize?

    init(cornerRadius: CGFloat?, bounds: CGRect? = nil, size: CGSize? = nil) {
        self.cornerRadius = cornerRadius
        self.bounds = bounds
        self.size = size
    }

    func path(in rect: CGRect) -> Path {
        if let cornerRadius {
            let shown = size.map { CGRect(origin: rect.origin, size: $0) } ?? rect
            return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: shown)
        }
        return Path(bounds ?? rect.insetBy(dx: -100_000, dy: -100_000))
    }
}

/// What the overview reports to the pages: where each card's page goes, and
/// its scrolling area, outside which pages are cut off so they don't cover
/// the overview's header.
private struct BrowserTabOverviewLayout: PreferenceKey {
    struct Value {
        var cards: [UUID: Anchor<CGRect>] = [:]
        /// How opaque each card is while swiped or dragged (1 when absent),
        /// for its page, which is drawn in another layer.
        var opacities: [UUID: Double] = [:]
        var viewport: Anchor<CGRect>?
    }

    static var defaultValue: Value { Value() }

    static func reduce(value: inout Value, nextValue: () -> Value) {
        let next = nextValue()
        value.cards.merge(next.cards) { $1 }
        value.opacities.merge(next.opacities) { $0 * $1 }
        value.viewport = next.viewport ?? value.viewport
    }
}

/// Uses the compact navigation control-group treatment where SwiftUI exposes
/// it, while preserving the native focus-driven control group on tvOS.
private struct BrowserNavigationControlGroupStyle: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(tvOS)
        content
        #else
        content.controlGroupStyle(.navigation)
        #endif
    }
}

/// The overview's chrome: a scrolling grid of cards over a material, with the
/// overview's bar along the bottom. The cards hold no page of their own; each
/// reports where its tab's page goes.
private struct BrowserTabOverview: View {
    let items: [BrowserTabItem]
    let selection: Binding<UUID>
    let onClose: (UUID) -> Void
    let onMove: ((UUID, Int) -> Void)?
    let newTabControl: AnyView?
    /// The size of the tab area, which every page has.
    let pageSize: CGSize
    let select: (UUID) -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let spacing: CGFloat = 16
                let columns = max(2, Int((geometry.size.width + spacing) / (220 + spacing)))
                let width = (geometry.size.width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
                // Cards are 2:3 in portrait and 3:2 in landscape, whatever the
                // window's exact shape; each page fills its card.
                let previewHeight = pageSize.height >= pageSize.width ? width * 3 / 2 : width * 2 / 3
                ScrollView {
                    BrowserTabOverviewGrid(items: items, columns: columns, width: width, spacing: spacing,
                                           onMove: onMove, onClose: onClose) { item, moveBy in
                        BrowserTabOverviewCard(item: item, width: width, previewHeight: previewHeight,
                                               isActive: selection.wrappedValue == item.id,
                                               onSelect: { select(item.id) },
                                               onClose: item.isPinned ? nil : { onClose(item.id) },
                                               onMoveBy: moveBy)
                    }
                    .padding(.vertical)
                }
                // Adds the viewport to what the cards inside report.
                .transformAnchorPreference(key: BrowserTabOverviewLayout.self, value: .bounds) { layout, viewport in
                    layout.viewport = viewport
                }
            }
            .padding(.horizontal)

            BrowserTabOverviewBar(tabCount: items.count, secondary: newTabControl, confirm: dismiss)
        }
        .background(.regularMaterial)
    }
}

/// The tab system's controls in the system's Liquid Glass where it has it
/// (iOS, macOS and tvOS 26), and a material before that and on visionOS,
/// whose own glass the window already provides. One look for every bar and
/// control the tab system draws, never a custom background.
private struct BrowserTabGlass<S: Shape>: ViewModifier {
    let shape: S
    var isInteractive = false

    func body(content: Content) -> some View {
        #if os(visionOS)
        content.background(.thinMaterial, in: shape)
        #else
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, *) {
            content.glassEffect(isInteractive ? .regular.interactive() : .regular, in: shape)
        } else {
            content.background(.thinMaterial, in: shape)
        }
        #endif
    }
}

/// A tab-system button in glass: `isProminent` for the confirming action
/// (the overview's Done), tinted as the system tints it.
private struct BrowserTabGlassButtonStyle: ViewModifier {
    var isProminent = false

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(visionOS)
        if isProminent { content.buttonStyle(.borderedProminent) } else { content.buttonStyle(.bordered) }
        #else
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, *) {
            if isProminent { content.buttonStyle(.glassProminent) } else { content.buttonStyle(.glass) }
        } else if isProminent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
        #endif
    }
}

/// Lets neighbouring glass controls blend as the system's do.
private struct BrowserTabGlassGroup<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if os(visionOS)
        content()
        #else
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, *) {
            GlassEffectContainer { content() }
        } else {
            content()
        }
        #endif
    }
}

/// The overview's bar. Its controls have fixed roles, so their order is
/// always the same: the secondary action (new tab) on the leading edge, the
/// tab count in the middle, and the confirming action (Done) on the trailing
/// edge as a prominent check mark. Spacing is the platform's standard padding.
private struct BrowserTabOverviewBar: View {
    let tabCount: Int
    /// An optional secondary action, such as opening a new tab.
    let secondary: AnyView?
    /// Closes the overview.
    let confirm: () -> Void

    var body: some View {
        BrowserTabGlassGroup {
            HStack {
                HStack {
                    if let secondary {
                        secondary
                            .menuIndicator(.hidden)
                            .buttonBorderShape(.circle)
                            .modifier(BrowserTabGlassButtonStyle())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(tabCount == 1 ? "1 Tab" : "\(tabCount) Tabs")
                    .font(.headline)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .modifier(BrowserTabGlass(shape: Capsule()))
                    .accessibilityAddTraits(.isHeader)

                Button(action: confirm) {
                    Image(systemName: "checkmark")
                        .font(.headline.weight(.semibold))
                        .padding(6)
                }
                .buttonBorderShape(.circle)
                .modifier(BrowserTabGlassButtonStyle(isProminent: true))
                .accessibilityLabel("Done")
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding()
        }
    }
}

/// A card: the area the tab's own page is laid over (the pages layer also
/// draws its close button there), and the tab's title below it.
private struct BrowserTabOverviewCard: View {
    static var cornerRadius: CGFloat { 18 }

    let item: BrowserTabItem
    let width: CGFloat
    let previewHeight: CGFloat
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: (() -> Void)?
    /// Moves this tab by an offset in the tab order, for accessibility.
    let onMoveBy: ((Int) -> Void)?

    var body: some View {
        selectable {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                    .fill(.background)
                    .frame(width: width, height: previewHeight)
                    .anchorPreference(key: BrowserTabOverviewLayout.self, value: .bounds) {
                        .init(cards: [item.id: $0])
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                            .stroke(isActive ? Color.accentColor : Color.primary.opacity(0.10),
                                    lineWidth: isActive ? 2 : 0.5)
                    }
                    .shadow(color: .black.opacity(0.08), radius: 6, y: 2)

                HStack(spacing: 4) {
                    if let systemImage = item.systemImage {
                        Image(systemName: systemImage).imageScale(.small)
                    }
                    Text(item.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.footnote.weight(.medium))
                .frame(width: width)
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Open \(item.title)")
        // For UI tests: every card, whatever its tab's title.
        .accessibilityIdentifier("browser-tab-overview-card")
        .accessibilityActions {
            if let onMoveBy {
                Button("Move Left") { onMoveBy(-1) }
                Button("Move Right") { onMoveBy(1) }
            }
            if let onClose {
                Button("Close") { onClose() }
            }
        }
        #if os(tvOS)
        .focusSection()
        #endif
    }

    /// Opens the tab when the card is chosen. On tvOS that is a focusable
    /// button. Elsewhere it is a tap, which a swipe or drag cancels (a
    /// button would also fire at the end of a quick swipe to close, opening
    /// the tab instead); it is still a button to accessibility.
    @ViewBuilder
    private func selectable<Label: View>(@ViewBuilder _ label: () -> Label) -> some View {
        #if os(tvOS)
        Button(action: onSelect, label: label)
            .buttonStyle(.plain)
        #else
        label()
            .onTapGesture(perform: onSelect)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, onSelect)
        #endif
    }
}

/// A card's close button, drawn by the pages layer over the card's
/// top-trailing corner so it sits above the page: round and translucent.
private struct BrowserTabCardCloseButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.caption2.weight(.bold))
                .frame(width: 24, height: 24)
                .modifier(BrowserTabGlass(shape: Circle(), isInteractive: true))
                // A small mark, as Safari draws it, with a finger-sized target.
                .padding(10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close \(title)")
    }
}

/// The overview's card grid. Where `onMove` is given, a card can be dragged
/// (on touch, after a long press) to a new place: the other cards reflow live
/// and the move is committed once, on drop. An unpinned card can be swiped
/// off sideways to close it: a finger on touch screens, two fingers on a
/// trackpad.
private struct BrowserTabOverviewGrid<Card: View>: View {
    let items: [BrowserTabItem]
    let columns: Int
    let width: CGFloat
    let spacing: CGFloat
    let onMove: ((UUID, Int) -> Void)?
    let onClose: (UUID) -> Void
    /// The card for a tab, given how to move it by an offset (for
    /// accessibility), or `nil` when tabs can't be moved.
    @ViewBuilder let card: (BrowserTabItem, ((Int) -> Void)?) -> Card

    @State private var drag = BrowserTabDragState()

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(width), spacing: spacing), count: columns),
                  spacing: spacing) {
            ForEach(drag.ordered(items)) { item in
                cell(item)
            }
        }
        .modifier(BrowserTabReorderingArea(items: items, drag: drag, onMove: onMove))
    }

    private func cell(_ item: BrowserTabItem) -> some View {
        let moveBy: ((Int) -> Void)? = onMove == nil ? nil : { offset in move(item.id, by: offset) }
        var swipe = BrowserTabSwipeToClose(id: item.id, width: width, isClosable: !item.isPinned) {
            onClose(item.id)
        } content: {
            card(item, moveBy)
        }
        // A reorder drag is over by the time a card is swiped, even if the
        // system never reported its end.
        swipe.onBegin = { drag.endIfStale() }
        return swipe
            .modifier(BrowserTabCardOpacity(id: item.id, opacity: drag.draggingID == item.id ? 0.45 : 1))
            .modifier(BrowserTabReorderable(id: item.id, items: items, drag: drag, onMove: onMove))
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              items.indices.contains(index + offset) else { return }
        onMove?(id, index + offset)
    }
}

/// Lets a tab (a card, or a tab in the tab bar) be dragged to a new place
/// among `items` when `onMove` is given: the others make way live, and the
/// move is committed once, on drop.
private struct BrowserTabReorderable: ViewModifier {
    let id: UUID
    let items: [BrowserTabItem]
    let drag: BrowserTabDragState
    let onMove: ((UUID, Int) -> Void)?

    func body(content: Content) -> some View {
        #if os(tvOS)
        content
        #else
        if let onMove {
            content
                .onDrag { drag.begin(id, order: items.map(\.id)) }
                .onDrop(of: [.text], delegate: BrowserTabCardDropDelegate(target: id, drag: drag) {
                    drag.finish(items: items, onMove: onMove)
                })
        } else {
            content
        }
        #endif
    }
}

/// The area tabs are reordered in: animates the others making way, ends a
/// drag dropped between tabs, and forgets the live order once the committed
/// order arrives.
private struct BrowserTabReorderingArea: ViewModifier {
    let items: [BrowserTabItem]
    let drag: BrowserTabDragState
    let onMove: ((UUID, Int) -> Void)?

    func body(content: Content) -> some View {
        content
            .animation(.spring(response: 0.3, dampingFraction: 0.86), value: drag.liveOrder)
            #if !os(tvOS)
            .onDrop(of: [.text], delegate: BrowserTabGridDropDelegate {
                if let onMove { drag.finish(items: items, onMove: onMove) }
            })
            #endif
            .onChange(of: items.map(\.id)) {
                // The committed order has arrived; show it rather than the copy.
                if drag.draggingID == nil { drag.liveOrder = nil }
            }
            .onDisappear { drag.reset() }
    }
}

/// The tab being dragged and the order shown meanwhile.
@MainActor
@Observable
private final class BrowserTabDragState {
    var draggingID: UUID?
    var liveOrder: [UUID]?

    /// `items` in the order shown: the live order while dragging. Tabs
    /// opened while dragging go last; closed ones drop out.
    func ordered(_ items: [BrowserTabItem]) -> [BrowserTabItem] {
        guard let liveOrder else { return items }
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return liveOrder.compactMap { byID[$0] } + items.filter { !liveOrder.contains($0.id) }
    }

    /// Ends the drag on a drop, committing the move if the tab moved.
    func finish(items: [BrowserTabItem], onMove: (UUID, Int) -> Void) {
        guard let id = draggingID else { return }
        draggingID = nil
        guard let index = liveOrder?.firstIndex(of: id),
              items.firstIndex(where: { $0.id == id }) != index else {
            liveOrder = nil
            return
        }
        // `liveOrder` stays until the new order arrives in `items`, so the
        // tabs don't jump back for a frame.
        onMove(id, index)
    }

    #if !os(tvOS)
    /// Starts dragging `id`. The drag's item provider holds a token that
    /// ends the drag when the system lets go of it, so a drag cancelled
    /// outside any drop target doesn't leave its card dimmed and the grid
    /// reordered.
    func begin(_ id: UUID, order: [UUID]) -> NSItemProvider {
        assert(draggingID == nil, "a reorder drag began while the last one was never reported as ended")
        draggingID = id
        liveOrder = order
        let token = BrowserTabDragToken(id: id) { [weak self] id in self?.cancel(id) }
        let provider = NSItemProvider()
        let data = Data(id.uuidString.utf8)
        provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier,
                                            visibility: .ownProcess) { completion in
            withExtendedLifetime(token) { completion(data, nil) }
            return nil
        }
        return provider
    }
    #endif

    /// Forgets a drag the system never reported the end of, once something
    /// else (a swipe) shows it is over: no card stays dimmed, no live order
    /// stays in place of the real one.
    func endIfStale() {
        if draggingID != nil { reset() }
    }

    /// Ends a drag that is still in progress without moving anything.
    func cancel(_ id: UUID) {
        guard draggingID == id else { return }
        reset()
    }

    func reset() {
        draggingID = nil
        liveOrder = nil
    }
}

/// Reports, on the main actor, when the drag holding it is over.
private final class BrowserTabDragToken: Sendable {
    let id: UUID
    let onEnd: @MainActor @Sendable (UUID) -> Void

    init(id: UUID, onEnd: @escaping @MainActor @Sendable (UUID) -> Void) {
        self.id = id
        self.onEnd = onEnd
    }

    deinit {
        let id = id, onEnd = onEnd
        Task { @MainActor in onEnd(id) }
    }
}

#if !os(tvOS)
/// Reflows the grid as a dragged card passes over another one.
private struct BrowserTabCardDropDelegate: DropDelegate {
    let target: UUID
    let drag: BrowserTabDragState
    let finish: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingID = drag.draggingID, draggingID != target, var order = drag.liveOrder,
              let from = order.firstIndex(of: draggingID),
              let to = order.firstIndex(of: target) else { return }
        order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        drag.liveOrder = order
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        finish()
        return true
    }
}

private struct BrowserTabGridDropDelegate: DropDelegate {
    let finish: () -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        finish()
        return true
    }
}
#endif

/// Lets a card be swiped off sideways to close it: with a finger on touch
/// screens, with two fingers on a trackpad. Only a mostly horizontal swipe
/// counts, so vertical scrolling is unaffected. As with the system's swipe
/// to delete, a card closes when pulled far enough or flicked fast enough,
/// however short the flick. A pinned card follows with resistance and
/// springs back.
private struct BrowserTabSwipeToClose<Content: View>: View {
    let id: UUID
    let width: CGFloat
    let isClosable: Bool
    let onClose: () -> Void
    /// Called as a swipe starts to move the card.
    var onBegin: () -> Void = {}
    @ViewBuilder let content: () -> Content

    /// The swipe's position, or where a card is flung away to.
    @State private var offset: CGFloat = 0
    @State private var isFlungAway = false

    var body: some View {
        content()
            .offset(x: offset)
            .modifier(BrowserTabCardOpacity(id: id, opacity: 1 - min(0.7, abs(offset) / (width * 1.4))))
            #if os(iOS)
            .gesture(BrowserTabTouchSwipe(onChange: follow, onEnd: settle))
            #elseif os(visionOS)
            // No UIKit recognizers in SwiftUI here: a drag with the same rules.
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        follow(value.translation.width)
                    }
                    .onEnded { value in settle(at: offset == 0 ? 0 : value.translation.width, velocity: value.velocity.width) }
            )
            #elseif os(macOS)
            .overlay(BrowserTabTrackpadSwipe(onChange: follow, onEnd: { settle(at: $0, velocity: 0) }))
            #endif
    }

    private func follow(_ translation: CGFloat) {
        guard !isFlungAway else { return }
        if offset == 0 { onBegin() }
        offset = isClosable ? translation : translation / 4
    }

    /// Ends a swipe that has moved the card by `translation`, with the finger
    /// moving at `velocity` (points per second) as it lifted.
    private func settle(at translation: CGFloat, velocity: CGFloat) {
        guard !isFlungAway else { return }
        let isFlick = abs(translation) > 10 && abs(velocity) > 500 && (velocity < 0) == (translation < 0)
        let projected = translation + velocity * 0.25
        guard isClosable, abs(translation) > width * 0.45 || isFlick || abs(projected) > width * 1.1 else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { offset = 0 }
            return
        }
        // Carry on from where the card is, then fling it off.
        isFlungAway = true
        let direction: CGFloat = (isFlick ? velocity : translation) < 0 ? -1 : 1
        withAnimation(.easeOut(duration: 0.18)) {
            offset = direction * width * 1.6
        } completion: {
            onClose()
        }
    }
}

#if os(iOS)
/// A horizontal pan over a card. It only begins for a mostly horizontal
/// movement, and the scroll view's own pan waits for it to fail, so a
/// sideways swipe is never taken over by scrolling (which cancelled quick
/// swipes in a scrollable overview) and vertical scrolling is unaffected.
/// A drag to reorder starts with a long press, which this doesn't take.
private struct BrowserTabTouchSwipe: UIGestureRecognizerRepresentable {
    let onChange: (CGFloat) -> Void
    /// The translation and the horizontal velocity at the end (zero for a
    /// cancelled pan).
    let onEnd: (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        let translation = pan.translation(in: pan.view).x
        switch pan.state {
        case .began, .changed: onChange(translation)
        case .ended: onEnd(translation, pan.velocity(in: pan.view).x)
        // Taken over (a scroll, a drag to reorder): settle where it is, so a
        // card already pulled far enough still closes and any other springs
        // back.
        case .cancelled: onEnd(translation, 0)
        default: break
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            // By the distance moved so far, which a slow drag has as surely as a
            // fast one (its velocity can still be zero here), and by velocity
            // when no distance is reported yet.
            let moved = pan.translation(in: pan.view), velocity = pan.velocity(in: pan.view)
            let sideways = abs(moved.x) + abs(velocity.x) * 0.05
            let upright = abs(moved.y) + abs(velocity.y) * 0.05
            return sideways > upright
        }

        /// Alongside anything but scrolling: the system's drag-and-drop
        /// recognizers on each card (lifting, adding items), which can still be
        /// waiting after a drag to reorder, must not hold a swipe back.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            !(other is UIPanGestureRecognizer && other.view is UIScrollView)
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other is UIPanGestureRecognizer && other.view is UIScrollView
        }
    }
}
#endif

#if os(macOS)
/// Reports two-finger horizontal trackpad swipes over a card. Vertical
/// scrolling, and anything that is not a scroll, passes through.
private struct BrowserTabTrackpadSwipe: NSViewRepresentable {
    let onChange: (CGFloat) -> Void
    let onEnd: (CGFloat) -> Void

    func makeNSView(context: Context) -> SwipeView {
        let view = SwipeView()
        view.onChange = onChange
        view.onEnd = onEnd
        return view
    }

    func updateNSView(_ view: SwipeView, context: Context) {
        view.onChange = onChange
        view.onEnd = onEnd
    }

    final class SwipeView: NSView {
        var onChange: (CGFloat) -> Void = { _ in }
        var onEnd: (CGFloat) -> Void = { _ in }
        private var translation: CGFloat = 0
        private var isHorizontal: Bool?

        /// Takes only scroll events, so clicks, hovers and drags reach the
        /// card underneath.
        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp.currentEvent?.type == .scrollWheel ? super.hitTest(point) : nil
        }

        override func scrollWheel(with event: NSEvent) {
            // Only real trackpad gestures, not momentum or mouse wheels.
            guard event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else {
                return super.scrollWheel(with: event)
            }
            if event.phase.contains(.began) {
                translation = 0
                isHorizontal = nil
            }
            if isHorizontal == nil, event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 {
                isHorizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
            }
            guard isHorizontal == true else { return super.scrollWheel(with: event) }
            // Follow the fingers, whatever the scrolling direction setting.
            let fingers = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
            translation += fingers
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                onEnd(translation)
                translation = 0
                isHorizontal = nil
            } else {
                onChange(translation)
            }
        }
    }
}
#endif

/// The window's tab strip (on macOS, in the title bar): the tabs share its
/// width as the system's window tabs do (``BrowserTabStripLayout``), and
/// past their minimum width it scrolls a tab at a time, with the tabs
/// scrolled off shown as slivers at each edge. The selected tab is always
/// whole: the strip scrolls to it whenever it changes, a tab opens, or the
/// strip is resized. Trackpads and mouse wheels scroll it; a tab dragged to
/// either edge scrolls it too; the new-tab control stays at the trailing
/// end, outside the tabs.
public struct BrowserTabBar: View {
    public let items: [BrowserTabItem]
    public let selection: Binding<UUID>
    public let onClose: (UUID) -> Void
    /// Moves a tab to an index among all tabs, dragged along the bar. `nil`
    /// leaves the tabs in place.
    public let onMove: ((UUID, Int) -> Void)?
    private let newTabControl: AnyView?
    @State private var hoveredID: UUID?
    @State private var hoveredCloseID: UUID?
    @State private var drag = BrowserTabDragState()
    /// The first whole tab while the tabs overflow.
    @State private var first = 0
    @State private var width: CGFloat = 0
    /// Scrolls along while a dragged tab is held over an edge.
    @State private var edgeScroll: Task<Void, Never>?

    public init(items: [BrowserTabItem], selection: Binding<UUID>, onClose: @escaping (UUID) -> Void,
                onMove: ((UUID, Int) -> Void)? = nil) {
        self.items = items
        self.selection = selection
        self.onClose = onClose
        self.onMove = onMove
        self.newTabControl = nil
    }

    public init<NewTabControl: View>(
        items: [BrowserTabItem], selection: Binding<UUID>, onClose: @escaping (UUID) -> Void,
        onMove: ((UUID, Int) -> Void)? = nil, @ViewBuilder newTabControl: () -> NewTabControl
    ) {
        self.items = items
        self.selection = selection
        self.onClose = onClose
        self.onMove = onMove
        self.newTabControl = AnyView(newTabControl())
    }

    private var layout: BrowserTabStripLayout {
        BrowserTabStripLayout(count: items.count, width: width, first: first)
    }

    public var body: some View {
        HStack(spacing: 4) {
            GeometryReader { geometry in
                tabs(height: geometry.size.height)
                    .onChange(of: geometry.size.width, initial: true) { width = geometry.size.width }
            }
            .padding(.horizontal, 2).padding(.vertical, 2)
            .modifier(BrowserTabGlass(shape: Capsule()))
            if let newTabControl {
                newTabControl.modifier(BrowserTabStripControlStyle())
            }
        }
        .padding(.horizontal, 4).padding(.vertical, 3)
        // The selected tab is always whole.
        .onChange(of: BrowserTabStripReveal(selection: selection.wrappedValue, ids: items.map(\.id), width: width),
                  initial: true) { reveal() }
        .animation(.easeOut(duration: 0.2), value: first)
    }

    private func tabs(height: CGFloat) -> some View {
        let shown = drag.ordered(items)
        let layout = BrowserTabStripLayout(count: shown.count, width: width, first: first)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                switch layout.slot(of: index) {
                case .tab(let x, let tabWidth):
                    tab(item, previous: index > layout.first ? shown[index - 1] : nil)
                        .frame(width: tabWidth, height: height)
                        .opacity(drag.draggingID == item.id ? 0.45 : 1)
                        .modifier(BrowserTabReorderable(id: item.id, items: items, drag: drag, onMove: onMove))
                        .offset(x: x)
                case .sliver(let x):
                    sliver(item, isLeading: index < layout.first)
                        .frame(width: BrowserTabStripLayout.sliverWidth, height: height)
                        .offset(x: x)
                }
            }
            if layout.isOverflowing {
                edge(step: -1, height: height)
                edge(step: 1, height: height)
                    .offset(x: width - BrowserTabStripLayout.edgeWidth)
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .clipped()
        .modifier(BrowserTabReorderingArea(items: items, drag: drag, onMove: onMove))
        #if os(macOS)
        .overlay(BrowserTabStripScroll { scroll(by: $0) })
        #endif
    }

    /// A tab scrolled off an edge: a thin line that shows the tab when
    /// clicked.
    private func sliver(_ item: BrowserTabItem, isLeading: Bool) -> some View {
        Button { selection.wrappedValue = item.id } label: {
            Rectangle()
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 1)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isLeading ? .leading : .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        #if !os(tvOS)
        .help(item.title)
        #endif
    }

    /// An edge's sliver area, which scrolls the strip while a dragged tab is
    /// held over it.
    @ViewBuilder
    private func edge(step: Int, height: CGFloat) -> some View {
        #if os(tvOS)
        EmptyView()
        #else
        Color.clear
            .frame(width: BrowserTabStripLayout.edgeWidth, height: height)
            .allowsHitTesting(drag.draggingID != nil)
            .onDrop(of: [.text], delegate: BrowserTabEdgeDropDelegate(
                enter: { startEdgeScroll(step) },
                exit: stopEdgeScroll,
                drop: { stopEdgeScroll(); if let onMove { drag.finish(items: items, onMove: onMove) } }
            ))
        #endif
    }

    private func startEdgeScroll(_ step: Int) {
        edgeScroll?.cancel()
        edgeScroll = Task {
            while !Task.isCancelled {
                scroll(by: step)
                try? await Task.sleep(for: .milliseconds(350))
            }
        }
    }

    private func stopEdgeScroll() {
        edgeScroll?.cancel()
        edgeScroll = nil
    }

    /// Scrolls the strip by `step` tabs.
    private func scroll(by step: Int) {
        let range = layout.firstRange
        first = min(max(layout.first + step, range.lowerBound), range.upperBound)
    }

    private func reveal() {
        guard let index = items.firstIndex(where: { $0.id == selection.wrappedValue }) else { return }
        let target = layout.first(revealing: index)
        if target != first { first = target }
    }

    private func tab(_ item: BrowserTabItem, previous: BrowserTabItem?) -> some View {
        let active = selection.wrappedValue == item.id
        let hovered = hoveredID == item.id
        let separator = previous.map {
            !active && selection.wrappedValue != $0.id && !hovered && hoveredID != $0.id
        } ?? false
        let button = Button { selection.wrappedValue = item.id } label: {
            ZStack(alignment: .leading) {
                if separator { Rectangle().fill(Color.secondary.opacity(0.35)).frame(width: 1, height: 14) }
                ZStack {
                    Text(item.title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 30)
                    HStack(spacing: 0) {
                        Group {
                            if item.isPinned {
                                Image(systemName: "house.fill")
                            } else if hovered {
                                closeButton(for: item)
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: 18, height: 18)
                        Spacer(minLength: 0)
                        Color.clear.frame(width: 18, height: 18)
                    }
                    .padding(.horizontal, 10)
                }
                .padding(.vertical, 5)
            }
            .background(Capsule().fill(!active && hovered ? Color.primary.opacity(0.07) : .clear))
        }
        .buttonStyle(.plain)
        .modifier(BrowserTabActiveStyle(isActive: active))
        #if os(tvOS)
        return button
        #else
        return button.onHover { hoveredID = $0 ? item.id : nil }
        #endif
    }

    @ViewBuilder
    private func closeButton(for item: BrowserTabItem) -> some View {
        let button = Button { onClose(item.id) } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 16, height: 16)
                .background(Circle().fill(
                    hoveredCloseID == item.id ? Color.primary.opacity(0.10) : .clear
                ))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close \(item.title)")

        #if os(tvOS)
        button
        #else
        button.onHover { hoveredCloseID = $0 ? item.id : nil }
        #endif
    }
}

/// The new-tab control at the strip's end: a borderless icon, whether it
/// is a button or a menu.
private struct BrowserTabStripControlStyle: ViewModifier {
    func body(content: Content) -> some View {
        #if os(tvOS)
        content
        #else
        content
            .menuIndicator(.hidden)
            .buttonStyle(.borderless)
            .fixedSize()
            .padding(.horizontal, 4)
        #endif
    }
}

/// What the strip scrolls to the selected tab on.
private struct BrowserTabStripReveal: Equatable {
    let selection: UUID
    let ids: [UUID]
    let width: CGFloat
}

#if !os(tvOS)
/// Reports a dragged tab entering, leaving or dropped on a strip edge.
private struct BrowserTabEdgeDropDelegate: DropDelegate {
    let enter: () -> Void
    let exit: () -> Void
    let drop: () -> Void

    func dropEntered(info: DropInfo) { enter() }
    func dropExited(info: DropInfo) { exit() }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        drop()
        return true
    }
}
#endif

#if os(macOS)
/// Turns horizontal scrolling over the strip (a trackpad's two fingers, or a
/// mouse wheel, which scrolls vertically) into scrolling a tab at a time.
/// Everything that is not a scroll passes through.
private struct BrowserTabStripScroll: NSViewRepresentable {
    let scroll: (Int) -> Void

    func makeNSView(context: Context) -> ScrollView {
        let view = ScrollView()
        view.scroll = scroll
        return view
    }

    func updateNSView(_ view: ScrollView, context: Context) { view.scroll = scroll }

    final class ScrollView: NSView {
        var scroll: (Int) -> Void = { _ in }
        private var pending: CGFloat = 0
        /// The distance one tab's step takes.
        private let step: CGFloat = 40

        override func hitTest(_ point: NSPoint) -> NSView? {
            NSApp.currentEvent?.type == .scrollWheel ? super.hitTest(point) : nil
        }

        override func scrollWheel(with event: NSEvent) {
            if event.phase.contains(.began) { pending = 0 }
            // A mouse wheel scrolls vertically; along the strip that means sideways.
            let delta = abs(event.scrollingDeltaX) >= abs(event.scrollingDeltaY)
                ? event.scrollingDeltaX : event.scrollingDeltaY
            pending += event.hasPreciseScrollingDeltas ? delta : delta * step
            // Content follows the fingers: moving them left shows tabs further right.
            while abs(pending) >= step {
                scroll(pending < 0 ? 1 : -1)
                pending -= pending < 0 ? -step : step
            }
        }
    }
}
#endif

private struct BrowserTabActiveStyle: ViewModifier {
    let isActive: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(visionOS)
        if isActive {
            content.background(Capsule().fill(.regularMaterial)
                .overlay(Capsule().stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)))
        } else {
            content
        }
        #else
        if #available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *) {
            if isActive {
                content.glassEffect(.regular)
            } else {
                content
            }
        } else if isActive {
            content.background(Capsule().fill(.regularMaterial)
                .overlay(Capsule().stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)))
        } else {
            content
        }
        #endif
    }
}
#else
public enum BrowserTabToolbarPlacement: Sendable {
    case leading, principal, trailing
}

public extension View {
    /// The tab system's controls for the selected tab. GTK windows show the
    /// native tab bar and header controls instead, so these add nothing.
    func browserTabControls<Controls: View>(@ViewBuilder _ controls: () -> Controls) -> some View {
        self
    }

    /// An action belonging to a page. GTK windows have no per-page navigation
    /// bar, so the selected tab's page actions go in the window header's
    /// page slots.
    func browserPageToolbarItem<Item: View>(
        id: String, placement: BrowserTabToolbarPlacement,
        @ViewBuilder content: @escaping () -> Item
    ) -> some View {
        GTKBrowserTabToolbarItem(content: self, placement: placement, accessory: content())
    }
}

private struct GTKBrowserTabToolbarItem<Content: View, Accessory: View>: View, PrimitiveView {
    typealias Body = Never
    let content: Content
    let placement: BrowserTabToolbarPlacement
    let accessory: Accessory

    var body: Never { fatalError("GTKBrowserTabToolbarItem is a platform-rendered primitive view") }
}

public extension Scene {
    /// The tab containers' keyboard commands (``BrowserTabShortcut``). GNOME
    /// apps have no menu bar, so each container registers them as its
    /// window's accelerators instead, and the scene needs nothing more.
    func browserTabCommands() -> Self { self }
}

private extension BrowserTabToolbarPlacement {
    var gtkDataKey: String {
        switch self {
        case .leading: "gtk-swift-browser-toolbar-leading"
        case .principal: "gtk-swift-browser-toolbar-principal"
        case .trailing: "gtk-swift-browser-toolbar-trailing"
        }
    }
}

public struct BrowserTabContainer<Content: View>: View, PrimitiveView {
    public typealias Body = Never
    public let items: [BrowserTabItem]
    public let selection: Binding<UUID>
    public let onClose: (UUID) -> Void
    /// Moves a tab to an index among all tabs, from the native tab bar or
    /// overview (AdwTabView reordering).
    public let onMove: ((UUID, Int) -> Void)?
    private let newTabControl: AnyView?
    private let onNewTab: (() -> Void)?
    /// Reopens the tab closed last; `nil` when there is none.
    private let onReopenClosedTab: (() -> Void)?
    public let content: (BrowserTabItem) -> Content

    public init(items: [BrowserTabItem], selection: Binding<UUID>, onClose: @escaping (UUID) -> Void,
                onMove: ((UUID, Int) -> Void)? = nil,
                overviewPresented: Binding<Bool>? = nil, onNewTab: (() -> Void)? = nil,
                onReopenClosedTab: (() -> Void)? = nil,
                @ViewBuilder content: @escaping (BrowserTabItem) -> Content) {
        self.items = items
        self.selection = selection
        self.onClose = onClose
        self.onMove = onMove
        self.newTabControl = nil
        self.onNewTab = onNewTab
        self.onReopenClosedTab = onReopenClosedTab
        self.content = content
    }

    public init<NewTabControl: View>(
        items: [BrowserTabItem], selection: Binding<UUID>, onClose: @escaping (UUID) -> Void,
        onMove: ((UUID, Int) -> Void)? = nil,
        overviewPresented: Binding<Bool>? = nil, onNewTab: (() -> Void)? = nil,
        onReopenClosedTab: (() -> Void)? = nil,
        @ViewBuilder newTabControl: () -> NewTabControl,
        @ViewBuilder content: @escaping (BrowserTabItem) -> Content
    ) {
        self.items = items
        self.selection = selection
        self.onClose = onClose
        self.onMove = onMove
        self.newTabControl = AnyView(newTabControl())
        self.onNewTab = onNewTab
        self.onReopenClosedTab = onReopenClosedTab
        self.content = content
    }

    public var body: Never { fatalError("BrowserTabContainer is a platform-rendered primitive view") }
}

public struct BrowserTabBar: View {
    public typealias Body = Never
    public let items: [BrowserTabItem]
    public let selection: Binding<UUID>
    public let onClose: (UUID) -> Void
    /// Moves a tab. GTK windows show the container's own AdwTabBar, which
    /// reorders through the container (`page-reordered`).
    public let onMove: ((UUID, Int) -> Void)?

    public init(items: [BrowserTabItem], selection: Binding<UUID>, onClose: @escaping (UUID) -> Void,
                onMove: ((UUID, Int) -> Void)? = nil) {
        self.items = items
        self.selection = selection
        self.onClose = onClose
        self.onMove = onMove
    }

    /// GTK windows show the container's own new-tab control.
    public init<NewTabControl: View>(
        items: [BrowserTabItem], selection: Binding<UUID>, onClose: @escaping (UUID) -> Void,
        onMove: ((UUID, Int) -> Void)? = nil, @ViewBuilder newTabControl: () -> NewTabControl
    ) {
        self.init(items: items, selection: selection, onClose: onClose, onMove: onMove)
    }

    public var body: Never { fatalError("BrowserTabBar is a platform-rendered primitive view") }
}

private final class BrowserTabCallbacks {
    let pages: [(UUID, OpaquePointer)]
    let selection: Binding<UUID>
    let onClose: (UUID) -> Void
    let onMove: ((UUID, Int) -> Void)?

    init(pages: [(UUID, OpaquePointer)], selection: Binding<UUID>, onClose: @escaping (UUID) -> Void,
         onMove: ((UUID, Int) -> Void)?) {
        self.pages = pages
        self.selection = selection
        self.onClose = onClose
        self.onMove = onMove
    }
}

private final class BrowserNewTabCallbacks {
    let view: UnsafeMutablePointer<GtkWidget>
    let action: () -> Void

    init(view: UnsafeMutablePointer<GtkWidget>, action: @escaping () -> Void) {
        self.view = view
        self.action = action
    }
}

private func makeNativeTabView(items: [BrowserTabItem], selection: Binding<UUID>,
                               onClose: @escaping (UUID) -> Void,
                               onMove: ((UUID, Int) -> Void)? = nil,
                               contents: [UUID: UnsafeMutablePointer<GtkWidget>] = [:]) -> UnsafeMutablePointer<GtkWidget> {
    let view = swift_adw_tab_view_new()!
    var pages: [(UUID, OpaquePointer)] = []
    for item in items {
        let pageContent = contents[item.id] ?? gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
        let page = swift_adw_tab_view_append(view, pageContent)!
        item.title.withCString { swift_adw_tab_page_set_title(page, $0) }
        swift_adw_tab_view_set_page_pinned(view, page, item.isPinned ? 1 : 0)
        swift_adw_tab_page_set_live_thumbnail(page, 1)
        pages.append((item.id, page))
        if item.id == selection.wrappedValue { swift_adw_tab_view_set_selected_page(view, page) }
    }
    let callbacks = Unmanaged.passRetained(BrowserTabCallbacks(
        pages: pages, selection: selection, onClose: onClose, onMove: onMove
    )).toOpaque()
    g_object_set_data_full(UnsafeMutableRawPointer(view).assumingMemoryBound(to: GObject.self),
                           "swift-browser-tab-callbacks", callbacks) { pointer in
        if let pointer { Unmanaged<BrowserTabCallbacks>.fromOpaque(pointer).release() }
    }
    g_signal_connect_data(gpointer(view), "notify::selected-page",
        unsafeBitCast({ (object: gpointer?, _: gpointer?, data: gpointer?) in
            guard let object, let data else { return }
            let state = Unmanaged<BrowserTabCallbacks>.fromOpaque(data).takeUnretainedValue()
            let widget = UnsafeMutableRawPointer(object).assumingMemoryBound(to: GtkWidget.self)
            guard let selected = swift_adw_tab_view_get_selected_page(widget),
                  let match = state.pages.first(where: { $0.1 == selected }),
                  state.selection.wrappedValue != match.0 else { return }
            state.selection.wrappedValue = match.0
        } as @convention(c) (gpointer?, gpointer?, gpointer?) -> Void, to: GCallback.self), callbacks, nil,
        GConnectFlags(rawValue: 0))
    g_signal_connect_data(gpointer(view), "close-page",
        unsafeBitCast({ (_: gpointer?, page: OpaquePointer?, data: gpointer?) -> gboolean in
            guard let page, let data else { return 0 }
            let state = Unmanaged<BrowserTabCallbacks>.fromOpaque(data).takeUnretainedValue()
            guard let match = state.pages.first(where: { $0.1 == page }) else { return 0 }
            state.onClose(match.0); return 1
        } as @convention(c) (gpointer?, OpaquePointer?, gpointer?) -> gboolean, to: GCallback.self), callbacks, nil,
        GConnectFlags(rawValue: 0))
    // Dragging a tab in the native tab bar or overview reorders it; the
    // app's own order follows, as with the other backends' overview.
    g_signal_connect_data(gpointer(view), "page-reordered",
        unsafeBitCast({ (_: gpointer?, page: OpaquePointer?, position: gint, data: gpointer?) in
            guard let page, let data else { return }
            let state = Unmanaged<BrowserTabCallbacks>.fromOpaque(data).takeUnretainedValue()
            guard let match = state.pages.first(where: { $0.1 == page }) else { return }
            state.onMove?(match.0, Int(position))
        } as @convention(c) (gpointer?, OpaquePointer?, gint, gpointer?) -> Void, to: GCallback.self), callbacks, nil,
        GConnectFlags(rawValue: 0))
    swift_adw_tab_view_invalidate_thumbnails(view)
    return view
}

private func browserToolbarData(
    _ key: String,
    in widget: UnsafeMutablePointer<GtkWidget>
) -> gpointer? {
    let object = UnsafeMutableRawPointer(widget).assumingMemoryBound(to: GObject.self)
    if let data = g_object_get_data(object, key) { return data }
    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        if let data = browserToolbarData(key, in: current) { return data }
        child = gtk_widget_get_next_sibling(current)
    }
    return nil
}

extension BrowserTabContainer: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        adw_init()
        var contents: [UUID: UnsafeMutablePointer<GtkWidget>] = [:]
        for item in items {
            // The same per-page state the other backends give their pages.
            let isSelected = item.id == selection.wrappedValue
            let page = content(item)
                .environment(\.isBrowserTabToolbarActive, isSelected)
                .environment(\.isBrowserTabVisible, isSelected)
            contents[item.id] = UnsafeMutableRawPointer(gtkRenderView(page))
                .assumingMemoryBound(to: GtkWidget.self)
        }
        let view = makeNativeTabView(items: items, selection: selection, onClose: onClose,
                                     onMove: onMove, contents: contents)
        let overview = swift_adw_tab_overview_new(view, view)!
        let bar = swift_adw_tab_bar_new(view)!
        let button = swift_adw_tab_button_new(view)!
        let object = UnsafeMutableRawPointer(overview).assumingMemoryBound(to: GObject.self)
        if let newTabControl {
            let newTabWidget = UnsafeMutableRawPointer(gtkRenderAnyView(newTabControl))
                .assumingMemoryBound(to: GtkWidget.self)
            g_object_set_data_full(object, "gtk-swift-browser-new-tab-control",
                                   g_object_ref_sink(gpointer(newTabWidget))) { g_object_unref($0) }
        }
        // The overview's own new-tab button, unless the app gave its own control
        // (one set of overview controls).
        if let onNewTab, newTabControl == nil {
            swift_adw_tab_overview_set_enable_new_tab(overview, 1)
            let action = Unmanaged.passRetained(BrowserNewTabCallbacks(view: view, action: onNewTab)).toOpaque()
            g_object_set_data_full(object, "gtk-swift-new-tab-action", action) { pointer in
                if let pointer { Unmanaged<BrowserNewTabCallbacks>.fromOpaque(pointer).release() }
            }
            g_signal_connect_data(gpointer(overview), "create-tab",
                unsafeBitCast({ (_: gpointer?, data: gpointer?) -> OpaquePointer? in
                    guard let data else { return nil }
                    let state = Unmanaged<BrowserNewTabCallbacks>.fromOpaque(data).takeUnretainedValue()
                    let placeholder = gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
                    let page = swift_adw_tab_view_append(state.view, placeholder)
                    "New Tab".withCString { swift_adw_tab_page_set_title(page, $0) }
                    swift_adw_tab_page_set_live_thumbnail(page, 1)
                    state.action()
                    return page
                } as @convention(c) (gpointer?, gpointer?) -> OpaquePointer?, to: GCallback.self),
                action, nil, GConnectFlags(rawValue: 0))
        }
        gtk_widget_set_hexpand(bar, 1)
        gtk_widget_set_vexpand(bar, 0)
        g_object_set_data(object, "gtk-swift-self-contained-window-chrome", gpointer(overview))
        g_signal_connect_data(gpointer(overview), "notify::root",
            unsafeBitCast({ (object: gpointer?, _: gpointer?, _: gpointer?) in
                guard let object else { return }
                let widget = UnsafeMutableRawPointer(object).assumingMemoryBound(to: GtkWidget.self)
                gtkClaimSelfContainedWindowChrome(widget)
            } as @convention(c) (gpointer?, gpointer?, gpointer?) -> Void, to: GCallback.self),
            nil, nil, GConnectFlags(rawValue: 0))
        g_object_set_data(object, "gtk-swift-browser-tab-view", gpointer(view))
        g_object_set_data_full(object, "gtk-swift-browser-tab-bar", g_object_ref_sink(gpointer(bar))) {
            g_object_unref($0)
        }
        g_object_set_data_full(object, "gtk-swift-browser-tab-button", g_object_ref_sink(gpointer(button))) {
            g_object_unref($0)
        }
        if let selectedContent = contents[selection.wrappedValue] {
            for key in ["gtk-swift-browser-toolbar-leading", "gtk-swift-browser-toolbar-principal",
                        "gtk-swift-browser-toolbar-trailing"] {
                if let accessory = browserToolbarData(key, in: selectedContent) {
                    g_object_set_data_full(object, key, g_object_ref(accessory)) { g_object_unref($0) }
                }
            }
        }
        gtkRegisterBrowserTabShortcuts(on: overview, view: view, target: BrowserTabCommandTarget(
            items: items, selection: selection, onClose: onClose,
            onNewTab: onNewTab, onReopenClosedTab: onReopenClosedTab))
        return OpaquePointer(overview)
    }
}

/// The tab commands (``BrowserTabShortcut``) as window accelerators while the
/// container's widget exists. GNOME apps have no menu bar, so these are
/// accelerators alone. AdwTabView already moves between tabs with Ctrl+Tab
/// and Ctrl+Shift+Tab, so those aren't registered twice. Closing the last tab
/// closes the window.
private func gtkRegisterBrowserTabShortcuts(on widget: UnsafeMutablePointer<GtkWidget>,
                                            view: UnsafeMutablePointer<GtkWidget>,
                                            target: BrowserTabCommandTarget) {
    let windowID = getCurrentEnvironment().windowID
    let registrations = BrowserTabShortcut.all.compactMap { shortcut -> ShortcutRegistrationID? in
        if shortcut == .nextTab || shortcut == .previousTab { return nil }
        // Without `onNewTab`, Ctrl+T belongs to the app's own new-tab control.
        if shortcut == .newTab, target.onNewTab == nil { return nil }
        let action: () -> Void
        if shortcut == .closeTab {
            action = {
                if target.items.count > 1 {
                    target.perform(.closeTab)
                } else if let root = gtk_widget_get_root(view) {
                    gtk_window_close(UnsafeMutableRawPointer(root).assumingMemoryBound(to: GtkWindow.self))
                }
            }
        } else {
            action = { target.perform(shortcut) }
        }
        return KeyboardShortcutRegistry.shared.register(
            KeyboardShortcut(shortcut.key, modifiers: shortcut.modifiers), windowID: windowID, action: action)
    }
    let unregister = Unmanaged.passRetained(ClosureBox {
        registrations.forEach(KeyboardShortcutRegistry.shared.unregister(id:))
    }).toOpaque()
    g_signal_connect_data(
        gpointer(widget), "destroy",
        unsafeBitCast({ (_: gpointer?, data: gpointer?) in
            guard let data else { return }
            Unmanaged<ClosureBox>.fromOpaque(data).takeUnretainedValue().closure()
        } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
        unregister,
        { (data: gpointer?, _: UnsafeMutablePointer<GClosure>?) in
            if let data { Unmanaged<ClosureBox>.fromOpaque(data).release() }
        },
        GConnectFlags(rawValue: 0))
}

public struct BrowserHistoryControls: View, PrimitiveView {
    public typealias Body = Never
    let canGoBack: () -> Bool
    let canGoForward: () -> Bool
    let goBack: () -> Void
    let goForward: () -> Void

    public init(canGoBack: @autoclosure @escaping () -> Bool,
                canGoForward: @autoclosure @escaping () -> Bool,
                goBack: @escaping () -> Void, goForward: @escaping () -> Void) {
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.goBack = goBack
        self.goForward = goForward
    }

    public var body: Never { fatalError("BrowserHistoryControls is a platform-rendered primitive view") }
}

extension BrowserHistoryControls: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0)!
        gtk_widget_add_css_class(box, "linked")
        let state = BrowserHistoryControlState(
            canGoBack: canGoBack, canGoForward: canGoForward,
            goBack: goBack, goForward: goForward
        )
        let back = UnsafeMutableRawPointer(gtkRenderView(
            Button(action: { state.navigateBack() }) { Image(systemName: "chevron.left") }
                .accessibilityLabel("Back")
        )).assumingMemoryBound(to: GtkWidget.self)
        let forward = UnsafeMutableRawPointer(gtkRenderView(
            Button(action: { state.navigateForward() }) { Image(systemName: "chevron.right") }
                .accessibilityLabel("Forward")
        )).assumingMemoryBound(to: GtkWidget.self)
        state.back = gtkFirstButton(in: back) ?? back
        state.forward = gtkFirstButton(in: forward) ?? forward
        state.refresh()
        let gtkBox = UnsafeMutableRawPointer(box).assumingMemoryBound(to: GtkBox.self)
        gtk_box_append(gtkBox, back)
        gtk_box_append(gtkBox, forward)
        return OpaquePointer(box)
    }
}

private func gtkFirstButton(in widget: UnsafeMutablePointer<GtkWidget>) -> UnsafeMutablePointer<GtkWidget>? {
    if String(cString: g_type_name(gtk_swift_get_widget_type(widget))) == "GtkButton" { return widget }
    var child = gtk_widget_get_first_child(widget)
    while let current = child {
        if let button = gtkFirstButton(in: current) { return button }
        child = gtk_widget_get_next_sibling(current)
    }
    return nil
}

@MainActor
private final class BrowserHistoryControlState {
    let canGoBack: () -> Bool
    let canGoForward: () -> Bool
    let goBack: () -> Void
    let goForward: () -> Void
    var back: UnsafeMutablePointer<GtkWidget>?
    var forward: UnsafeMutablePointer<GtkWidget>?

    init(canGoBack: @escaping () -> Bool, canGoForward: @escaping () -> Bool,
         goBack: @escaping () -> Void, goForward: @escaping () -> Void) {
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.goBack = goBack
        self.goForward = goForward
    }

    func navigateBack() {
        goBack()
        refresh()
    }

    func navigateForward() {
        goForward()
        refresh()
    }

    func refresh() {
        if let back { gtk_widget_set_sensitive(back, canGoBack() ? 1 : 0) }
        if let forward { gtk_widget_set_sensitive(forward, canGoForward() ? 1 : 0) }
    }
}

extension GTKBrowserTabToolbarItem: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        let contentWidget = UnsafeMutableRawPointer(gtkRenderView(content))
            .assumingMemoryBound(to: GtkWidget.self)
        let object = UnsafeMutableRawPointer(contentWidget).assumingMemoryBound(to: GObject.self)
        let key = placement.gtkDataKey
        let box: UnsafeMutablePointer<GtkWidget>
        if let existing = g_object_get_data(object, key) {
            box = UnsafeMutableRawPointer(existing).assumingMemoryBound(to: GtkWidget.self)
        } else {
            box = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6)!
            g_object_set_data_full(object, key, g_object_ref_sink(gpointer(box))) { g_object_unref($0) }
        }
        gtk_box_append(UnsafeMutableRawPointer(box).assumingMemoryBound(to: GtkBox.self),
                       UnsafeMutableRawPointer(gtkRenderView(accessory))
            .assumingMemoryBound(to: GtkWidget.self))
        return OpaquePointer(contentWidget)
    }
}

extension BrowserTabBar: GTKRenderable {
    public func gtkCreateWidget() -> OpaquePointer {
        adw_init()
        let view = makeNativeTabView(items: items, selection: selection, onClose: onClose)
        let bar = swift_adw_tab_bar_new(view)!
        gtk_widget_set_hexpand(bar, 1)
        gtk_widget_set_halign(bar, GTK_ALIGN_FILL)
        return OpaquePointer(bar)
    }
}
#endif
