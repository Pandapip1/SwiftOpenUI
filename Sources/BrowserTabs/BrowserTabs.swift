import Foundation

import SwiftOpenUI
#if BACKEND_GTK
import BackendGTK4
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

private struct BrowserTabOverviewPreviewKey: EnvironmentKey {
    static let defaultValue = false
}

public extension EnvironmentValues {
    /// True while a tab's live content is rendered inside an overview card.
    /// Browser chrome should use this to avoid becoming part of the preview.
    var isBrowserTabOverviewPreview: Bool {
        get { self[BrowserTabOverviewPreviewKey.self] }
        set { self[BrowserTabOverviewPreviewKey.self] = newValue }
    }
}

#if !BACKEND_GTK
public struct BrowserTabContainer<Content: View>: View {
    public let items: [BrowserTabItem]
    public let selection: Binding<UUID>
    public let onClose: (UUID) -> Void
    private let content: (BrowserTabItem) -> Content
    private let overviewPresented: Binding<Bool>?
    @State private var showingOverview = false
    @Namespace private var overviewTransition

    public init(items: [BrowserTabItem], selection: Binding<UUID>, onClose: @escaping (UUID) -> Void,
                overviewPresented: Binding<Bool>? = nil,
                @ViewBuilder content: @escaping (BrowserTabItem) -> Content) {
        self.items = items
        self.selection = selection
        self.onClose = onClose
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
        Group {
            if isShowingOverview {
                macOverview
                    .transition(.opacity)
            } else {
                mountedPages
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
                BrowserTabOverview(items: items, selection: selection, onClose: onClose, content: content) {
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
                    .accessibilityHidden(selection.wrappedValue != item.id)
                    .matchedGeometryEffect(id: item.id, in: overviewTransition)
            }
        }
    }

    @ToolbarContentBuilder
    private var overviewToolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { isShowingOverview.toggle() } label: { Image(systemName: "square.grid.2x2") }
                .accessibilityLabel(isShowingOverview ? "Close Tab Overview" : "Tab Overview")
        }
    }

    #if os(macOS)
    private var macOverview: some View {
        GeometryReader { geometry in
            let columns = max(2, Int(geometry.size.width / 320))
            let spacing: CGFloat = 24
            let width = (geometry.size.width - 64 - CGFloat(columns - 1) * spacing) / CGFloat(columns)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(width)), count: columns), spacing: spacing) {
                    ForEach(items) { item in
                        BrowserTabOverviewCard(item: item, width: width,
                                               isActive: selection.wrappedValue == item.id,
                                               onSelect: { select(item.id) },
                                               onClose: item.isPinned ? nil : { onClose(item.id) }) {
                            content(item)
                                .allowsHitTesting(false)
                                .environment(\.isBrowserTabOverviewPreview, true)
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

private struct BrowserTabOverview<Content: View>: View {
    let items: [BrowserTabItem]
    let selection: Binding<UUID>
    let onClose: (UUID) -> Void
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
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(width)), count: columns), spacing: spacing) {
                            ForEach(items) { item in
                                BrowserTabOverviewCard(item: item, width: width,
                                                       isActive: selection.wrappedValue == item.id,
                                                       onSelect: { selection.wrappedValue = item.id; dismiss() },
                                                       onClose: item.isPinned ? nil : { onClose(item.id) }) {
                                    content(item)
                                        .allowsHitTesting(false)
                                        .environment(\.isBrowserTabOverviewPreview, true)
                                }
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Tabs")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: dismiss) }
            }
        }
    }
}

private struct BrowserTabOverviewCard<LivePreview: View>: View {
    let item: BrowserTabItem
    let width: CGFloat
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: (() -> Void)?
    @ViewBuilder let livePreview: () -> LivePreview

    init(item: BrowserTabItem, width: CGFloat, isActive: Bool, onSelect: @escaping () -> Void,
         onClose: (() -> Void)?, @ViewBuilder livePreview: @escaping () -> LivePreview) {
        self.item = item; self.width = width; self.isActive = isActive
        self.onSelect = onSelect; self.onClose = onClose; self.livePreview = livePreview
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onSelect)
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.caption.weight(.bold))
                            .frame(width: 28, height: 28).background(Circle().fill(.regularMaterial))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close \(item.title)")
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 44)

            Button(action: onSelect) {
                livePreview()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel("Open \(item.title)")
        }
        .frame(width: width, height: width / 0.72)
        .clipped()
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isActive ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isActive ? 3 : 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        #if os(tvOS)
        .focusSection()
        #endif
    }

}

public struct BrowserTabBar: View {
    public let items: [BrowserTabItem]
    public let selection: Binding<UUID>
    public let onClose: (UUID) -> Void
    @State private var hoveredID: UUID?

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
                HStack(spacing: 6) {
                    if item.isPinned { Image(systemName: "house.fill") }
                    Text(item.title).lineLimit(1)
                    Spacer(minLength: 0)
                    if !item.isPinned && hovered {
                        Button { onClose(item.id) } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain)
                    }
                }.padding(.horizontal, 10).padding(.vertical, 5)
            }
            .background(Capsule().fill(active ? Color.primary.opacity(0.14) :
                                        (hovered ? Color.primary.opacity(0.07) : .clear)))
        }
        .buttonStyle(.plain)
        .modifier(BrowserTabActiveStyle(isActive: active))
        #if os(tvOS)
        return button
        #else
        return button.onHover { hoveredID = $0 ? item.id : nil }
        #endif
    }
}

private struct BrowserTabActiveStyle: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, tvOS 26.0, visionOS 26.0, *) {
            if isActive { content.glassEffect(.clear) } else { content }
        } else if isActive {
            content.background(Capsule().fill(.regularMaterial)
                .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.5)))
        } else {
            content
        }
    }
}
#else
public struct BrowserTabContainer<Content: View>: View, PrimitiveView {
    public typealias Body = Never
    public let items: [BrowserTabItem]
    public let selection: Binding<UUID>
    public let onClose: (UUID) -> Void
    public let content: (BrowserTabItem) -> Content

    public init(items: [BrowserTabItem], selection: Binding<UUID>, onClose: @escaping (UUID) -> Void,
                overviewPresented: Binding<Bool>? = nil,
                @ViewBuilder content: @escaping (BrowserTabItem) -> Content) {
        self.items = items
        self.selection = selection
        self.onClose = onClose
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
        pages.append((item.id, page))
        if item.id == selection.wrappedValue { swift_adw_tab_view_set_selected_page(view, page) }
    }
    let callbacks = Unmanaged.passRetained(BrowserTabCallbacks(pages: pages, selection: selection, onClose: onClose)).toOpaque()
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
    return view
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
        gtk_widget_set_hexpand(bar, 1)
        let object = UnsafeMutableRawPointer(overview).assumingMemoryBound(to: GObject.self)
        g_object_set_data(object, "gtk-swift-self-contained-window-chrome", gpointer(overview))
        g_object_set_data(object, "gtk-swift-browser-tab-view", gpointer(view))
        g_object_set_data_full(object, "gtk-swift-browser-tab-bar", g_object_ref_sink(gpointer(bar))) {
            g_object_unref($0)
        }
        g_object_set_data_full(object, "gtk-swift-browser-tab-button", g_object_ref_sink(gpointer(button))) {
            g_object_unref($0)
        }
        return OpaquePointer(overview)
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
