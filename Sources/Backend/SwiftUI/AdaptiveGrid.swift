#if canImport(SwiftUI)
import SwiftUI

/// A portable adaptive grid whose columns are never narrower than `minimumWidth`.
public struct AdaptiveGrid<Data: Identifiable, Content: View>: View {
    private let data: [Data]
    private let minimumWidth: CGFloat
    private let content: (Data) -> Content

    public init(_ data: [Data], minimumWidth: Double,
                @ViewBuilder content: @escaping (Data) -> Content) {
        self.data = data
        self.minimumWidth = minimumWidth
        self.content = content
    }

    public var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minimumWidth))]) {
            ForEach(data, content: content)
        }
    }
}
#endif
