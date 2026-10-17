import Foundation

import SwiftOpenUI
#if BACKEND_GTK
@_spi(SwiftOpenUIBackend) import BackendGTK4
import CGTK
import CAdwaita
#endif

public struct BrowserTabItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let isPinned: Bool

    public init(id: UUID, title: String, isPinned: Bool = false) {
        self.id = id
        self.title = title
        self.isPinned = isPinned
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

private struct BrowserTabOverviewPreviewKey: EnvironmentKey {
    static let defaultValue = false
}

private struct BrowserTabToolbarActiveKey: EnvironmentKey {
    static let defaultValue = true
}

public extension EnvironmentValues {
    /// True while a tab's live content is rendered inside an overview card.
    /// Browser chrome should use this to avoid becoming part of the preview.
    var isBrowserTabOverviewPreview: Bool {
        get { self[BrowserTabOverviewPreviewKey.self] }
        set { self[BrowserTabOverviewPreviewKey.self] = newValue }
    }


    /// True only for the selected tab while the normal browser view is shown.
    /// Tab content should conditionally contribute its contextual toolbar items
    /// using this value because inactive tabs remain mounted.
    var isBrowserTabToolbarActive: Bool {
        get { self[BrowserTabToolbarActiveKey.self] }
        set { self[BrowserTabToolbarActiveKey.self] = newValue }
    }
}

#if !BACKEND_GTK
public enum BrowserTabToolbarPlacement: Sendable {
    case leading, principal, trailing
}

@MainActor
private final class BrowserTabToolbarCoordinator: ObservableObject {
    struct Item: Identifiable {
        let id: String
        let tabID: UUID
        let placement: BrowserTabToolbarPlacement
        let content: AnyView
    }
    @Published var items: [String: Item] = [:]
    func set(_ item: Item) { items[item.id + item.tabID.uuidString] = item }
    func remove(id: String, tabID: UUID) { items[id + tabID.uuidString] = nil }
}

private struct BrowserTabToolbarCoordinatorKey: EnvironmentKey {
    static let defaultValue: BrowserTabToolbarCoordinator? = nil
}
private struct BrowserTabIdentityKey: EnvironmentKey { static let defaultValue: UUID? = nil }

private struct BrowserTabToolbarRegistration<Accessory: View>: ViewModifier {
    @Environment(\.browserTabToolbarCoordinator) private var coordinator
    @Environment(\.browserTabIdentity) private var tabID
    let id: String
    let placement: BrowserTabToolbarPlacement
    @ViewBuilder let accessory: () -> Accessory
    func body(content: Content) -> some View {
        content
            .onAppear { register() }
            .onDisappear {
                if let coordinator, let tabID { coordinator.remove(id: id, tabID: tabID) }
            }
    }
    private func register() {
        guard let coordinator, let tabID else { return }
        coordinator.set(.init(id: id, tabID: tabID, placement: placement,
                              content: AnyView(accessory())))
    }
}

private extension EnvironmentValues {
    var browserTabToolbarCoordinator: BrowserTabToolbarCoordinator? {
        get { self[BrowserTabToolbarCoordinatorKey.self] }
        set { self[BrowserTabToolbarCoordinatorKey.self] = newValue }
    }
    var browserTabIdentity: UUID? {
        get { self[BrowserTabIdentityKey.self] }
        set { self[BrowserTabIdentityKey.self] = newValue }
    }
}

public extension View {
    func browserTabToolbarItem<Accessory: View>(
        id: String, placement: BrowserTabToolbarPlacement,
        @ViewBuilder content: @escaping () -> Accessory
    ) -> some View {
        modifier(BrowserTabToolbarRegistration(id: id, placement: placement, accessory: content))
    }
}

public struct BrowserTabContainer<Content: View>: View {
    public let items: [BrowserTabItem]
    public let selection: Binding<UUID>
    public let onClose: (UUID) -> Void
    private let newTabControl: AnyView?
    private let onNewTab: (() -> Void)?
    private let content: (BrowserTabItem) -> Content
    private let overviewPresented: Binding<Bool>?
    @State private var showingOverview = false
    @Namespace private var overviewTransition
    @StateObject private var toolbarCoordinator = BrowserTabToolbarCoordinator()

    public init(items: [BrowserTabItem], selection: Binding<UUID>, onClose: @escaping (UUID) -> Void,
                overviewPresented: Binding<Bool>? = nil, onNewTab: (() -> Void)? = nil,
                @ViewBuilder content: @escaping (BrowserTabItem) -> Content) {
        self.items = items
        self.selection = selection
        self.onClose = onClose
        self.newTabControl = nil
        self.onNewTab = onNewTab
        self.overviewPresented = overviewPresented
        self.content = content
    }

    public init<NewTabControl: View>(
        items: [BrowserTabItem], selection: Binding<UUID>, onClose: @escaping (UUID) -> Void,
        overviewPresented: Binding<Bool>? = nil, onNewTab: (() -> Void)? = nil,
        @ViewBuilder newTabControl: () -> NewTabControl,
        @ViewBuilder content: @escaping (BrowserTabItem) -> Content
    ) {
        self.items = items
        self.selection = selection
        self.onClose = onClose
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
        #if os(macOS)
        ZStack {
            mountedPages
                .opacity(isShowingOverview ? 0 : 1)
                .allowsHitTesting(!isShowingOverview)
                .accessibilityHidden(isShowingOverview)
            if isShowingOverview {
                macOverview
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.86), value: isShowingOverview)
        .toolbar { overviewToolbar }
        #else
        mountedPages
            .toolbar { overviewToolbar }
            .fullScreenCover(isPresented: Binding(
                get: { isShowingOverview }, set: { isShowingOverview = $0 }
            )) {
                BrowserTabOverview(items: items, selection: selection, onClose: onClose,
                                   newTabControl: newTabControl, content: content) {
                    isShowingOverview = false
                }
            }
        #endif
    }

    private var mountedPages: some View {
        ZStack {
            ForEach(items) { item in
                content(item)
                    .opacity(selection.wrappedValue == item.id ? 1 : 0)
                    .allowsHitTesting(selection.wrappedValue == item.id)
                    // Embedded native surfaces such as WKWebView maintain their
                    // own backing view. Explicitly promote the selected page so
                    // insertion order cannot leave an inactive surface above it.
                    .zIndex(selection.wrappedValue == item.id ? 1 : 0)
                    .accessibilityHidden(selection.wrappedValue != item.id)
                    .environment(\.isBrowserTabToolbarActive,
                                 selection.wrappedValue == item.id && !isShowingOverview)
                    .environment(\.browserTabToolbarCoordinator, toolbarCoordinator)
                    .environment(\.browserTabIdentity, item.id)
                    .matchedGeometryEffect(id: item.id, in: overviewTransition)
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
        let contextualItems = toolbarCoordinator.items.values.filter {
            $0.tabID == selection.wrappedValue && !isShowingOverview
        }
        let leadingItems = contextualItems.filter { $0.placement == .leading }
        let principalItems = contextualItems.filter { $0.placement == .principal }
        let trailingItems = contextualItems.filter { $0.placement == .trailing }
        if !leadingItems.isEmpty {
            #if os(macOS) || os(iOS)
            if #available(macOS 26.0, iOS 26.0, *) { ToolbarSpacer(.fixed, placement: .navigation) }
            #endif
            ToolbarItem(placement: .automatic) {
                ControlGroup { ForEach(leadingItems) { $0.content } }
                    .controlGroupStyle(.navigation)
            }
        }
        if !principalItems.isEmpty {
            ToolbarItem(placement: .principal) {
                HStack { ForEach(principalItems) { $0.content } }
            }
        }
        if !trailingItems.isEmpty {
            ToolbarItem(placement: .primaryAction) {
                ControlGroup { ForEach(trailingItems) { $0.content } }
                    .controlGroupStyle(.navigation)
            }
            #if os(macOS) || os(iOS)
            if #available(macOS 26.0, iOS 26.0, *) { ToolbarSpacer(.fixed, placement: .primaryAction) }
            #endif
        }
        #if os(iOS)
        ToolbarItem(placement: .topBarTrailing) {
            tabManagementControl
        }
        #else
        ToolbarItem(placement: .primaryAction) {
            tabManagementControl
        }
        #endif
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

    #if os(macOS)
    private var macOverview: some View {
        GeometryReader { geometry in
            let columns = max(2, Int(geometry.size.width / 320))
            let spacing: CGFloat = 24
            let width = (geometry.size.width - 64 - CGFloat(columns - 1) * spacing) / CGFloat(columns)
            let contentAspectRatio = max(0.1, geometry.size.width / max(1, geometry.size.height))
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(width)), count: columns), spacing: spacing) {
                    ForEach(items) { item in
                        BrowserTabOverviewCard(item: item, width: width, aspectRatio: contentAspectRatio,
                                               isActive: selection.wrappedValue == item.id,
                                               onSelect: { select(item.id) },
                                               onClose: item.isPinned ? nil : { onClose(item.id) }) {
                            content(item)
                                .allowsHitTesting(false)
                                .environment(\.isBrowserTabOverviewPreview, true)
                                .environment(\.isBrowserTabToolbarActive, false)
                                .matchedGeometryEffect(id: item.id, in: overviewTransition)
                        }
                    }
                }
                .padding(32)
            }
            .background(Color.secondary.opacity(0.08))
        }
    }
    #endif

    private func select(_ id: UUID) {
        selection.wrappedValue = id
        isShowingOverview = false
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

private struct BrowserTabOverview<Content: View>: View {
    let items: [BrowserTabItem]
    let selection: Binding<UUID>
    let onClose: (UUID) -> Void
    let newTabControl: AnyView?
    let content: (BrowserTabItem) -> Content
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
                GeometryReader { geometry in
                    let columns = max(2, Int(geometry.size.width / 190))
                    let spacing: CGFloat = 16
                    let width = (geometry.size.width - 32 - CGFloat(columns - 1) * spacing) / CGFloat(columns)
                    let contentAspectRatio = max(0.1, geometry.size.width / max(1, geometry.size.height))
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(width)), count: columns), spacing: spacing) {
                            ForEach(items) { item in
                                BrowserTabOverviewCard(item: item, width: width, aspectRatio: contentAspectRatio,
                                                       isActive: selection.wrappedValue == item.id,
                                                       onSelect: { selection.wrappedValue = item.id; dismiss() },
                                                       onClose: item.isPinned ? nil : { onClose(item.id) }) {
                                    content(item)
                                        .allowsHitTesting(false)
                                        .environment(\.isBrowserTabOverviewPreview, true)
                                        .environment(\.isBrowserTabToolbarActive, false)
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Tabs")
            .toolbar {
                if let newTabControl {
                    ToolbarItem(placement: .primaryAction) {
                        newTabControl
                    }
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: dismiss) }
            }
        }
    }
}

private struct BrowserTabOverviewCard<LivePreview: View>: View {
    let item: BrowserTabItem
    let width: CGFloat
    let aspectRatio: CGFloat
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: (() -> Void)?
    @ViewBuilder let livePreview: () -> LivePreview
    @State private var closeHovered = false

    init(item: BrowserTabItem, width: CGFloat, aspectRatio: CGFloat, isActive: Bool, onSelect: @escaping () -> Void,
         onClose: (() -> Void)?, @ViewBuilder livePreview: @escaping () -> LivePreview) {
        self.item = item; self.width = width; self.aspectRatio = aspectRatio; self.isActive = isActive
        self.onSelect = onSelect; self.onClose = onClose; self.livePreview = livePreview
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Button(action: onSelect) {
                ZStack {
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            Color.clear.frame(width: 28, height: 28)
                            Text(item.title)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .center)
                            Color.clear.frame(width: 28, height: 28)
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 36)

                        livePreview()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                    }
                    Color.clear
                        .contentShape(Rectangle())
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel("Open \(item.title)")

            if let onClose {
                overviewCloseButton(action: onClose)
                    .accessibilityLabel("Close \(item.title)")
                    .padding(.top, 9)
                    .padding(.leading, 10)
            }
        }
        .frame(width: width, height: width / aspectRatio)
        .clipped()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        #if os(tvOS)
        .focusSection()
        #endif
    }

    @ViewBuilder
    private func overviewCloseButton(action: @escaping () -> Void) -> some View {
        let button = Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .semibold))
                .frame(width: 18, height: 18)
                .background(Circle().fill(closeHovered ? Color.primary.opacity(0.10) : .clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)

        #if os(tvOS)
        button
        #else
        button.onHover { closeHovered = $0 }
        #endif
    }

}

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
    func browserTabToolbarItem<Accessory: View>(
        id: String, placement: BrowserTabToolbarPlacement,
        @ViewBuilder content: @escaping () -> Accessory
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
    private let newTabControl: AnyView?
    private let onNewTab: (() -> Void)?
    public let content: (BrowserTabItem) -> Content

    public init(items: [BrowserTabItem], selection: Binding<UUID>, onClose: @escaping (UUID) -> Void,
                overviewPresented: Binding<Bool>? = nil, onNewTab: (() -> Void)? = nil,
                @ViewBuilder content: @escaping (BrowserTabItem) -> Content) {
        self.items = items
        self.selection = selection
        self.onClose = onClose
        self.newTabControl = nil
        self.onNewTab = onNewTab
        self.content = content
    }

    public init<NewTabControl: View>(
        items: [BrowserTabItem], selection: Binding<UUID>, onClose: @escaping (UUID) -> Void,
        overviewPresented: Binding<Bool>? = nil, onNewTab: (() -> Void)? = nil,
        @ViewBuilder newTabControl: () -> NewTabControl,
        @ViewBuilder content: @escaping (BrowserTabItem) -> Content
    ) {
        self.items = items
        self.selection = selection
        self.onClose = onClose
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

    init(pages: [(UUID, OpaquePointer)], selection: Binding<UUID>, onClose: @escaping (UUID) -> Void) {
        self.pages = pages
        self.selection = selection
        self.onClose = onClose
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
        pages: pages, selection: selection, onClose: onClose
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
            contents[item.id] = UnsafeMutableRawPointer(gtkRenderView(content(item)))
                .assumingMemoryBound(to: GtkWidget.self)
        }
        let view = makeNativeTabView(items: items, selection: selection, onClose: onClose,
                                     contents: contents)
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
