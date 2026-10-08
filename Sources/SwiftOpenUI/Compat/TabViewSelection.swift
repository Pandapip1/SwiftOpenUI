import Foundation

// SwiftUI's `TabView(selection:) { Page().tabItem { Label(…) }.tag(value) }` form, lowered onto the `Tab` model.

protocol AnyTabItemView {
    var anyTabContent: any View { get }
    var anyTabTitle: String { get }
}

/// The result of `.tabItem { }`. It is only read by `TabView(selection:)`; it never renders by itself.
public struct TabItemView<Content: View, L: View>: View, PrimitiveView, AnyTabItemView {
    public typealias Body = Never
    public let content: Content
    public let label: L

    var anyTabContent: any View { content }
    var anyTabTitle: String {
        for v in AlertActions.flatten(label) {
            if let l = v as? SwiftOpenUICore.Label { return l.title }
            if let t = v as? Text { return t.content }
        }
        return "Tab"
    }

    public var body: Never { fatalError("TabItemView is only meaningful inside TabView") }
}

extension View {
    public func tabItem<L: View>(@ViewBuilder _ label: () -> L) -> TabItemView<Self, L> {
        TabItemView(content: self, label: label())
    }
}

extension TabView {
    public init<S: Hashable, C: View>(selection: Binding<S>, @ViewBuilder content: () -> C) {
        var found: [(title: String, tag: AnyHashable?, content: any View)] = []
        Self.collect(content(), tag: nil, into: &found)
        let tags = found.enumerated().map { $0.element.tag ?? AnyHashable($0.offset) }
        let tabs = found.enumerated().map { i, t in
            AnyTab(Tab(t.title, id: "tab-\(i)") { AnyView(t.content) })
        }
        let index = Binding<Int>(
            get: { tags.firstIndex(of: AnyHashable(selection.wrappedValue)) ?? 0 },
            set: { i in
                guard tags.indices.contains(i), let value = tags[i].base as? S else { return }
                if value != selection.wrappedValue { selection.wrappedValue = value }
            })
        self.init(tabs: tabs, selectionIndex: index)
    }

    private static func collect(_ view: any View, tag: AnyHashable?, into out: inout [(title: String, tag: AnyHashable?, content: any View)]) {
        if let tagged = view as? AnyTagView {
            collect(tagged.anyTagContent, tag: tagged.anyTagValue, into: &out)
        } else if let item = view as? AnyTabItemView {
            out.append((item.anyTabTitle, tag, item.anyTabContent))
        } else if let multi = view as? MultiChildView {
            for child in multi.children { collect(child, tag: tag, into: &out) }
        }
    }
}
