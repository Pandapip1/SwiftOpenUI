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

public extension View {
    /// Installs the conventional new-tab command where the platform supports
    /// hardware keyboard shortcuts. The visible control remains unchanged on
    /// focus-only platforms such as tvOS.
    @ViewBuilder
    func browserNewTabKeyboardShortcut() -> some View {
        #if os(tvOS)
        self
        #else
        keyboardShortcut("t")
        #endif
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

private struct BrowserOnceVisibleTask<ID: Equatable & Sendable>: ViewModifier {
    @Environment(\.isBrowserTabVisible) private var isVisible
    let id: ID
    let action: @MainActor () async -> Void
    @State private var completedID: ID?

    func body(content: Content) -> some View {
        content.task(id: BrowserVisibleTaskKey(id: id, isVisible: isVisible)) {
            guard isVisible, completedID != id else { return }
            await action()
            if !Task.isCancelled { completedID = id }
        }
    }
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
    private let content: (BrowserTabItem) -> Content
    private let overviewPresented: Binding<Bool>?
    @State private var showingOverview = false
    @Environment(\.browserTabControls) private var tabControls

    public init(items: [BrowserTabItem], selection: Binding<UUID>, onClose: @escaping (UUID) -> Void,
                onMove: ((UUID, Int) -> Void)? = nil,
                overviewPresented: Binding<Bool>? = nil, onNewTab: (() -> Void)? = nil,
                @ViewBuilder content: @escaping (BrowserTabItem) -> Content) {
        self.items = items
        self.selection = selection
        self.onClose = onClose
        self.onMove = onMove
        self.newTabControl = nil
        self.onNewTab = onNewTab
        self.overviewPresented = overviewPresented
        self.content = content
    }

    public init<NewTabControl: View>(
        items: [BrowserTabItem], selection: Binding<UUID>, onClose: @escaping (UUID) -> Void,
        onMove: ((UUID, Int) -> Void)? = nil,
        overviewPresented: Binding<Bool>? = nil, onNewTab: (() -> Void)? = nil,
        @ViewBuilder newTabControl: () -> NewTabControl,
        @ViewBuilder content: @escaping (BrowserTabItem) -> Content
    ) {
        self.items = items
        self.selection = selection
        self.onClose = onClose
        self.onMove = onMove
        self.newTabControl = AnyView(newTabControl())
        self.onNewTab = onNewTab
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
        .modifier(BrowserTabControlsPlacement(controls: isShowingOverview ? nil : tabControls))
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: isShowingOverview)
        .toolbar { overviewToolbar }
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
                    let scale = area.width > 0 ? frame.width / area.width : 1
                    let isInteractive = isSelected && !isShowingOverview
                    content(item)
                        .frame(width: area.width, height: area.height)
                        .clipShape(BrowserTabPageClip(
                            cornerRadius: card.map { _ in BrowserTabOverviewCard.cornerRadius / max(scale, 0.01) }))
                        .scaleEffect(scale, anchor: .topLeading)
                        .offset(x: frame.minX, y: frame.minY)
                        .opacity(card != nil || isInteractive ? 1 : 0)
                        .transaction { transaction in
                            if !isSelected {
                                transaction.animation = nil
                                transaction.disablesAnimations = true
                            }
                        }
                        .allowsHitTesting(isInteractive)
                        .accessibilityHidden(!isInteractive)
                        // Embedded native surfaces such as WKWebView keep their own
                        // backing view; promote the selected page so insertion
                        // order cannot leave an inactive surface above it.
                        .zIndex(isSelected ? 1 : 0)
                        .environment(\.isBrowserTabToolbarActive, isInteractive)
                        .environment(\.isBrowserTabVisible, card != nil || isInteractive)
                }
                // Each card's close button, over its page's top-trailing corner.
                ForEach(items.filter { !$0.isPinned }) { item in
                    if let card = layout.cards[item.id].map({ proxy[$0] }) {
                        BrowserTabCardCloseButton(title: item.title) { onClose(item.id) }
                            .position(x: card.maxX - 22, y: card.minY + 22)
                            .zIndex(2)
                    }
                }
            }
            .frame(width: area.width, height: area.height, alignment: .topLeading)
            .mask(alignment: .topLeading) {
                BrowserTabPageClip(cornerRadius: nil, bounds: layout.viewport == nil ? nil : visible)
            }
        }
    }

    @ToolbarContentBuilder
    private var overviewToolbar: some ToolbarContent {
        #if os(tvOS)
        ToolbarItem(placement: .primaryAction) {
            Button { isShowingOverview.toggle() } label: { Image(systemName: "square.on.square") }
                .accessibilityLabel(isShowingOverview ? "Close Tab Overview" : "Tab Overview")
        }
        #else
        // Tab controls only. Pages put their own actions in their own
        // toolbars; the tab chrome never carries them. The overview has its
        // own bar with these controls, so they aren't shown twice.
        if !isShowingOverview {
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                tabManagementControl
            }
            #else
            ToolbarItem(placement: .primaryAction) {
                tabManagementControl
            }
            #endif
        }
        #endif
    }

    private var tabManagementControl: some View {
        ControlGroup {
            if let newTabControl {
                newTabControl
            }
            Button { isShowingOverview.toggle() } label: { Image(systemName: "square.on.square") }
                .accessibilityLabel(isShowingOverview ? "Close Tab Overview" : "Tab Overview")
        }
        .modifier(BrowserNavigationControlGroupStyle())
    }

    private func select(_ id: UUID) {
        selection.wrappedValue = id
        isShowingOverview = false
    }
}

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
            if let controls { controls }
        }
        #elseif os(tvOS)
        VStack(spacing: 0) {
            if let controls { controls }
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
private struct BrowserTabPageClip: Shape {
    /// The corner radius, when the page is in a card.
    var cornerRadius: CGFloat?
    /// The area to keep, in the shape's own coordinates; `nil` for all of it.
    var bounds: CGRect?

    func path(in rect: CGRect) -> Path {
        if let cornerRadius {
            return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).path(in: rect)
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
        var viewport: Anchor<CGRect>?
    }

    static var defaultValue: Value { Value() }

    static func reduce(value: inout Value, nextValue: () -> Value) {
        let next = nextValue()
        value.cards.merge(next.cards) { $1 }
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
                // Cards have the tab area's shape, so the page fits exactly.
                let previewHeight = width * pageSize.height / max(1, pageSize.width)
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
        HStack {
            HStack {
                if let secondary { secondary }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(tabCount == 1 ? "1 Tab" : "\(tabCount) Tabs")
                .font(.headline)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.thinMaterial, in: Capsule())
                .accessibilityAddTraits(.isHeader)

            Button(action: confirm) {
                Image(systemName: "checkmark")
                    .font(.headline.weight(.semibold))
                    .padding(6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Done")
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding()
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
                .font(.subheadline.weight(.medium))
                .frame(width: width)
            }
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Open \(item.title)")
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
                .font(.caption.weight(.bold))
                .frame(width: 28, height: 28)
                .background(.ultraThinMaterial, in: Circle())
                .contentShape(Circle())
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
            ForEach(orderedItems) { item in
                cell(item)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: drag.liveOrder)
        #if !os(tvOS)
        // A drop between cards still ends the drag.
        .onDrop(of: [.text], delegate: BrowserTabGridDropDelegate(finish: finishDrag))
        #endif
        .onChange(of: items.map(\.id)) {
            // The committed order has arrived; show it rather than the copy.
            if drag.draggingID == nil { drag.liveOrder = nil }
        }
        .onDisappear { drag.reset() }
    }

    private var orderedItems: [BrowserTabItem] {
        guard let liveOrder = drag.liveOrder else { return items }
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        // Tabs opened while dragging go last; closed ones drop out.
        return liveOrder.compactMap { byID[$0] } + items.filter { !liveOrder.contains($0.id) }
    }

    @ViewBuilder
    private func cell(_ item: BrowserTabItem) -> some View {
        let moveBy: ((Int) -> Void)? = onMove == nil ? nil : { offset in move(item.id, by: offset) }
        let swipeable = BrowserTabSwipeToClose(width: width, isClosable: !item.isPinned) {
            onClose(item.id)
        } content: {
            card(item, moveBy)
        }
        .opacity(drag.draggingID == item.id ? 0.45 : 1)
        #if os(tvOS)
        swipeable
        #else
        if onMove != nil {
            swipeable
                .onDrag { drag.begin(item.id, order: items.map(\.id)) }
                .onDrop(of: [.text], delegate: BrowserTabCardDropDelegate(target: item.id, drag: drag,
                                                                          finish: finishDrag))
        } else {
            swipeable
        }
        #endif
    }

    private func finishDrag() {
        guard let id = drag.draggingID else { return }
        drag.draggingID = nil
        guard let index = drag.liveOrder?.firstIndex(of: id),
              items.firstIndex(where: { $0.id == id }) != index else {
            drag.liveOrder = nil
            return
        }
        // `liveOrder` stays until the new order arrives in `items`, so the
        // cards don't jump back for a frame.
        onMove?(id, index)
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              items.indices.contains(index + offset) else { return }
        onMove?(id, index + offset)
    }
}

/// The card being dragged and the order shown meanwhile.
@MainActor
@Observable
private final class BrowserTabDragState {
    var draggingID: UUID?
    var liveOrder: [UUID]?

    #if !os(tvOS)
    /// Starts dragging `id`. The drag's item provider holds a token that
    /// ends the drag when the system lets go of it, so a drag cancelled
    /// outside any drop target doesn't leave its card dimmed and the grid
    /// reordered.
    func begin(_ id: UUID, order: [UUID]) -> NSItemProvider {
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
/// counts, so vertical scrolling is unaffected. A pinned card follows with
/// resistance and springs back.
private struct BrowserTabSwipeToClose<Content: View>: View {
    let width: CGFloat
    let isClosable: Bool
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    /// A trackpad swipe's position, or where a card is flung away to.
    @State private var settledOffset: CGFloat = 0
    @State private var isFlungAway = false
    #if os(iOS) || os(visionOS)
    /// A finger's position. It springs back by itself when the touch ends or
    /// is taken over, for instance by a drag to reorder.
    @GestureState(resetTransaction: Transaction(animation: .spring(response: 0.3, dampingFraction: 0.8)))
    private var touchOffset: CGFloat = 0
    #endif

    var body: some View {
        content()
            .offset(x: offset)
            .opacity(1 - min(0.7, abs(offset) / (width * 1.4)))
            #if os(iOS) || os(visionOS)
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .updating($touchOffset) { value, state, _ in
                        guard !isFlungAway, abs(value.translation.width) > abs(value.translation.height) else { return }
                        state = resisted(value.translation.width)
                    }
                    .onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        settle(at: value.translation.width, projected: value.predictedEndTranslation.width)
                    }
            )
            #elseif os(macOS)
            .overlay(BrowserTabTrackpadSwipe(
                onChange: { translation in
                    guard !isFlungAway else { return }
                    settledOffset = resisted(translation)
                },
                onEnd: { translation in settle(at: translation, projected: translation) }
            ))
            #endif
    }

    private var offset: CGFloat {
        #if os(iOS) || os(visionOS)
        isFlungAway ? settledOffset : touchOffset + settledOffset
        #else
        settledOffset
        #endif
    }

    private func resisted(_ translation: CGFloat) -> CGFloat {
        isClosable ? translation : translation / 4
    }

    private func settle(at translation: CGFloat, projected: CGFloat) {
        guard !isFlungAway else { return }
        guard isClosable, abs(translation) > width * 0.45 || abs(projected) > width * 1.1 else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { settledOffset = 0 }
            return
        }
        // Carry on from where the card is, then fling it off.
        isFlungAway = true
        settledOffset = translation
        let direction: CGFloat = (projected == 0 ? translation : projected) < 0 ? -1 : 1
        withAnimation(.easeOut(duration: 0.18)) {
            settledOffset = direction * width * 1.6
        } completion: {
            onClose()
        }
    }
}

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

public struct BrowserTabBar: View {
    public let items: [BrowserTabItem]
    public let selection: Binding<UUID>
    public let onClose: (UUID) -> Void
    @State private var hoveredID: UUID?
    @State private var hoveredCloseID: UUID?

    public init(items: [BrowserTabItem], selection: Binding<UUID>, onClose: @escaping (UUID) -> Void) {
        self.items = items
        self.selection = selection
        self.onClose = onClose
    }

    public var body: some View {
        GeometryReader { geometry in
            let width = max(100, (geometry.size.width - 12) / CGFloat(max(1, items.count)))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        tab(item, previous: index > 0 ? items[index - 1] : nil)
                            .frame(width: width)
                    }
                }
                .padding(.horizontal, 2).padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.05))
                    .overlay(Capsule().stroke(Color.primary.opacity(0.1), lineWidth: 0.5)))
                .padding(.horizontal, 4).padding(.vertical, 3)
                .frame(minWidth: geometry.size.width)
            }
        }
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

        #if os(tvOS)
        button
        #else
        button.onHover { hoveredCloseID = $0 ? item.id : nil }
        #endif
    }
}

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
    public let content: (BrowserTabItem) -> Content

    public init(items: [BrowserTabItem], selection: Binding<UUID>, onClose: @escaping (UUID) -> Void,
                onMove: ((UUID, Int) -> Void)? = nil,
                overviewPresented: Binding<Bool>? = nil, onNewTab: (() -> Void)? = nil,
                @ViewBuilder content: @escaping (BrowserTabItem) -> Content) {
        self.items = items
        self.selection = selection
        self.onClose = onClose
        self.onMove = onMove
        self.newTabControl = nil
        self.onNewTab = onNewTab
        self.content = content
    }

    public init<NewTabControl: View>(
        items: [BrowserTabItem], selection: Binding<UUID>, onClose: @escaping (UUID) -> Void,
        onMove: ((UUID, Int) -> Void)? = nil,
        overviewPresented: Binding<Bool>? = nil, onNewTab: (() -> Void)? = nil,
        @ViewBuilder newTabControl: () -> NewTabControl,
        @ViewBuilder content: @escaping (BrowserTabItem) -> Content
    ) {
        self.items = items
        self.selection = selection
        self.onClose = onClose
        self.onMove = onMove
        self.newTabControl = AnyView(newTabControl())
        self.onNewTab = onNewTab
        self.content = content
    }

    public var body: Never { fatalError("BrowserTabContainer is a platform-rendered primitive view") }
}

public struct BrowserTabBar: View {
    public typealias Body = Never
    public let items: [BrowserTabItem]
    public let selection: Binding<UUID>
    public let onClose: (UUID) -> Void

    public init(items: [BrowserTabItem], selection: Binding<UUID>, onClose: @escaping (UUID) -> Void) {
        self.items = items
        self.selection = selection
        self.onClose = onClose
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
        if let onNewTab {
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
        return OpaquePointer(overview)
    }
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
