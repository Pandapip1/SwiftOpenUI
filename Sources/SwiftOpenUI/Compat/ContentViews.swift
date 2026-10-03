import Foundation

// MARK: - ContentUnavailableView

/// SwiftUI's empty-state view: an icon and title, optional description, optional actions.
public struct ContentUnavailableView<L: View, D: View, A: View>: View {
    public typealias Body = _ContentUnavailableBody<L, D, A>
    let label: L
    let description: D
    let actions: A

    public init(@ViewBuilder label: () -> L,
                @ViewBuilder description: () -> D = { EmptyView() },
                @ViewBuilder actions: () -> A = { EmptyView() }) {
        self.label = label()
        self.description = description()
        self.actions = actions()
    }

    public var body: _ContentUnavailableBody<L, D, A> {
        _ContentUnavailableBody(label: label, description: description, actions: actions)
    }
}

public struct _ContentUnavailableBody<L: View, D: View, A: View>: View {
    let label: L
    let description: D
    let actions: A

    public var body: some View {
        VStack(spacing: 10) {
            label
            description.foregroundStyle(HierarchicalShapeStyle.secondary.approximatedColor)
            actions
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

extension ContentUnavailableView where L == SwiftOpenUI.Label, D == Text, A == EmptyView {
    public init(_ title: String, systemImage name: String, description: Text? = nil) {
        self.label = Label(title, systemImage: name)
        self.description = description ?? Text("")
        self.actions = EmptyView()
    }
}

extension ContentUnavailableView where L == SwiftOpenUI.Label, D == Text, A == EmptyView {
    /// "No results for …", as shown for an empty search.
    public static func search(text: String) -> ContentUnavailableView {
        ContentUnavailableView("No Results", systemImage: "magnifyingglass",
                               description: Text("No results for \u{201C}\(text)\u{201D}. Try a new search."))
    }

    public static var search: ContentUnavailableView {
        ContentUnavailableView("No Results", systemImage: "magnifyingglass",
                               description: Text("Check the spelling or try a new search."))
    }
}

// MARK: - LabeledContent

/// A title with a value or control on the trailing side, as used in settings forms.
public struct LabeledContent<C: View>: View {
    let title: String
    let content: C

    public init(_ title: String, @ViewBuilder content: () -> C) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        HStack {
            Text(title)
            Spacer()
            content
        }
    }
}

extension LabeledContent where C == Text {
    public init(_ title: String, value: String) {
        self.title = title
        self.content = Text(value)
    }
}

// MARK: - ShareLink

/// SwiftUI's share button. There is no system share sheet on desktop, so activating it copies the item to the clipboard.
public struct ShareLink<L: View>: View {
    let text: String
    let label: L

    public init(item: String, @ViewBuilder label: () -> L) {
        self.text = item
        self.label = label()
    }

    public init(item: URL, @ViewBuilder label: () -> L) {
        self.text = item.absoluteString
        self.label = label()
    }

    public var body: some View {
        let value = text
        return Button(action: { SystemServices.copyToClipboard(value) }, label: { label })
    }
}

extension ShareLink where L == SwiftOpenUI.Label {
    public init(item: String, subject: Text? = nil, message: Text? = nil) {
        self.text = item
        self.label = Label("Copy Link", systemImage: "link")
    }

    public init(item: URL, subject: Text? = nil, message: Text? = nil) {
        self.text = item.absoluteString
        self.label = Label("Copy Link", systemImage: "link")
    }
}

// MARK: - ForEach over any collection

extension ForEach where Data: Identifiable, ID == Data.ID {
    public init<C: RandomAccessCollection>(_ data: C, @ViewBuilder content: @escaping (Data) -> Content) where C.Element == Data {
        self.init(Array(data), content: content)
    }
}

extension ForEach {
    public init<C: RandomAccessCollection>(_ data: C, id: KeyPath<Data, ID>, @ViewBuilder content: @escaping (Data) -> Content) where C.Element == Data {
        self.init(Array(data), id: id, content: content)
    }
}
