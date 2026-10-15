/// A portable adaptive grid whose columns are never narrower than `minimumWidth`.
///
/// Unlike the renderer primitive, this has the same collection-driven API on
/// every SwiftOpenUI backend.
public struct AdaptiveGrid<Data: Identifiable, Content: View>: View {
    private let data: [Data]
    private let minimumWidth: Double
    private let content: (Data) -> Content

    public init(_ data: [Data], minimumWidth: Double,
                @ViewBuilder content: @escaping (Data) -> Content) {
        self.data = data
        self.minimumWidth = minimumWidth
        self.content = content
    }

    public var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumWidth))], data: data, content: content)
    }
}
