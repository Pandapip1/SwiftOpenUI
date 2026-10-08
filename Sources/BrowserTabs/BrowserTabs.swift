import Foundation

#if canImport(SwiftUI)
import SwiftUI
#else
import SwiftOpenUI
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

#if canImport(SwiftUI)
public struct BrowserTabContainer<Content: View>: View {
    public let items: [BrowserTabItem]
    public let selection: Binding<UUID>
    public let onClose: (UUID) -> Void
    private let content: Content
    @State private var showingOverview = false

    public init(items: [BrowserTabItem], selection: Binding<UUID>, onClose: @escaping (UUID) -> Void,
                @ViewBuilder content: () -> Content) {
        self.items = items
        self.selection = selection
        self.onClose = onClose
        self.content = content()
    }

    public var body: some View {
        content
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingOverview = true } label: { Image(systemName: "square.grid.2x2") }
                        .accessibilityLabel("Tab Overview")
                }
            }
            .sheet(isPresented: $showingOverview) {
                VStack {
                    ForEach(items) { item in
                        HStack {
                            Button(item.title) {
                                selection.wrappedValue = item.id
                                showingOverview = false
                            }
                            Spacer()
                            if !item.isPinned {
                                Button { onClose(item.id) } label: { Image(systemName: "xmark") }
                                    .accessibilityLabel("Close \(item.title)")
                            }
                        }
                    }
                }.padding()
            }
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
        return Button { selection.wrappedValue = item.id } label: {
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
        .onHover { hoveredID = $0 ? item.id : nil }
    }
}

private struct BrowserTabActiveStyle: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, iOS 26.0, *) {
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
    public let content: Content

    public init(items: [BrowserTabItem], selection: Binding<UUID>, onClose: @escaping (UUID) -> Void,
                @ViewBuilder content: () -> Content) {
        self.items = items
        self.selection = selection
        self.onClose = onClose
        self.content = content()
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
                               selectedContent: UnsafeMutablePointer<GtkWidget>? = nil) -> UnsafeMutablePointer<GtkWidget> {
    let view = swift_adw_tab_view_new()!
    var pages: [(UUID, OpaquePointer)] = []
    for item in items {
        let pageContent = item.id == selection.wrappedValue
            ? (selectedContent ?? gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!)
            : gtk_box_new(GTK_ORIENTATION_VERTICAL, 0)!
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
        let renderedContent = gtkRenderView(content)
        let contentWidget = UnsafeMutableRawPointer(renderedContent).assumingMemoryBound(to: GtkWidget.self)
        let view = makeNativeTabView(items: items, selection: selection, onClose: onClose,
                                     selectedContent: contentWidget)
        let overview = swift_adw_tab_overview_new(view, view)!
        let bar = swift_adw_tab_bar_new(view)!
        let button = swift_adw_tab_button_new(view)!
        // GtkWindow owns its custom titlebar separately from its content
        // hierarchy, so `overview.open` cannot resolve through ancestors once
        // the native button is seated in that titlebar. Connect the native
        // button directly to the overview it represents.
        g_signal_connect_data(gpointer(button), "clicked",
            unsafeBitCast({ (_: gpointer?, data: gpointer?) in
                guard let data else { return }
                let overview = UnsafeMutableRawPointer(data).assumingMemoryBound(to: GtkWidget.self)
                swift_adw_tab_overview_set_open(overview, 1)
            } as @convention(c) (gpointer?, gpointer?) -> Void, to: GCallback.self),
            gpointer(overview), nil, GConnectFlags(rawValue: 0))
        gtk_widget_set_hexpand(bar, 1)
        let object = UnsafeMutableRawPointer(overview).assumingMemoryBound(to: GObject.self)
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
