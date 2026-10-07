/// Placement for toolbar items.
public enum ToolbarItemPlacement: Equatable, Hashable {
    case leading
    case trailing
    case primaryAction
    /// The toolbar's centered/title region.  On desktop platforms this is
    /// the native header's flexible middle area.
    case principal
}

/// Visibility state for a toolbar container.
public enum ToolbarVisibility: Equatable {
    case automatic
    case visible
    case hidden
}

/// Simplified toolbar container targets.
public enum ToolbarPlacementTarget: Equatable {
    case automatic
    case navigationBar
    case bottomBar
    case tabBar
}

/// Stored toolbar configuration attached to a view tree.
public struct ToolbarConfiguration: Equatable {
    public let visibility: ToolbarVisibility?
    public let visibilityTarget: ToolbarPlacementTarget?
    public let removedPlacements: [ToolbarItemPlacement]

    public init(
        visibility: ToolbarVisibility? = nil,
        visibilityTarget: ToolbarPlacementTarget? = nil,
        removedPlacements: [ToolbarItemPlacement] = []
    ) {
        self.visibility = visibility
        self.visibilityTarget = visibilityTarget
        self.removedPlacements = removedPlacements
    }
}

/// Content that can appear in a toolbar.
///
/// This has the same composition model as SwiftUI's `ToolbarContent`: toolbar
/// items and groups are values in their own right, so applications can return
/// a reusable `some ToolbarContent` from a computed property and pass it to
/// `toolbar(content:)` without a builder-specific overload.
public protocol ToolbarContent {
    associatedtype Body: ToolbarContent

    @ToolbarContentBuilder var body: Self.Body { get }
}

/// The internal representation used while extracting platform toolbar items.
///
/// Keeping flattening out of the public `ToolbarContent` protocol is
/// intentional: it is renderer machinery, not part of SwiftUI's API.
private protocol _ToolbarContentPrimitive {
    var _toolbarItems: [AnyToolbarItem] { get }
}

private func flattenToolbarContent<Content: ToolbarContent>(_ content: Content) -> [AnyToolbarItem] {
    if let primitive = content as? any _ToolbarContentPrimitive {
        return primitive._toolbarItems
    }
    return flattenToolbarContent(content.body)
}

extension Never: ToolbarContent {}

/// Result builder for composing one or more toolbar items.
@resultBuilder
public enum ToolbarContentBuilder {
    public static func buildBlock() -> some ToolbarContent {
        _EmptyToolbarContent()
    }

    public static func buildBlock<Content: ToolbarContent>(
        _ content: Content
    ) -> Content {
        content
    }

    public static func buildExpression<Content: ToolbarContent>(
        _ expression: Content
    ) -> Content {
        expression
    }

    public static func buildOptional<Content: ToolbarContent>(
        _ component: Content?
    ) -> some ToolbarContent {
        _OptionalToolbarContent(component)
    }

    public static func buildEither<TrueContent: ToolbarContent, FalseContent: ToolbarContent>(
        first component: TrueContent
    ) -> _ConditionalToolbarContent<TrueContent, FalseContent> {
        .trueContent(component)
    }

    public static func buildEither<TrueContent: ToolbarContent, FalseContent: ToolbarContent>(
        second component: FalseContent
    ) -> _ConditionalToolbarContent<TrueContent, FalseContent> {
        .falseContent(component)
    }

    public static func buildArray<Content: ToolbarContent>(
        _ components: [Content]
    ) -> some ToolbarContent {
        _ToolbarContentArray(components)
    }

    public static func buildPartialBlock<Content: ToolbarContent>(
        first content: Content
    ) -> Content {
        content
    }

    public static func buildPartialBlock<Accumulated: ToolbarContent, Next: ToolbarContent>(
        accumulated: Accumulated,
        next: Next
    ) -> some ToolbarContent {
        _ToolbarContentPair(first: accumulated, second: next)
    }
}

private struct _EmptyToolbarContent: ToolbarContent, _ToolbarContentPrimitive {
    var body: Never { fatalError("Empty toolbar content has no body") }
    var _toolbarItems: [AnyToolbarItem] { [] }
}

private struct _ToolbarContentPair<First: ToolbarContent, Second: ToolbarContent>: ToolbarContent, _ToolbarContentPrimitive {
    let first: First
    let second: Second

    var body: Never { fatalError("Toolbar content pair has no body") }
    var _toolbarItems: [AnyToolbarItem] {
        flattenToolbarContent(first) + flattenToolbarContent(second)
    }
}

private struct _OptionalToolbarContent<Content: ToolbarContent>: ToolbarContent, _ToolbarContentPrimitive {
    let content: Content?

    init(_ content: Content?) {
        self.content = content
    }

    var body: Never { fatalError("Optional toolbar content is primitive") }
    var _toolbarItems: [AnyToolbarItem] {
        content.map(flattenToolbarContent) ?? []
    }
}

private struct _ToolbarContentArray<Content: ToolbarContent>: ToolbarContent, _ToolbarContentPrimitive {
    let content: [Content]

    init(_ content: [Content]) {
        self.content = content
    }

    var body: Never { fatalError("Toolbar content array is primitive") }
    var _toolbarItems: [AnyToolbarItem] {
        content.flatMap(flattenToolbarContent)
    }
}

/// The active branch of a conditional toolbar-content expression.
public enum _ConditionalToolbarContent<TrueContent: ToolbarContent, FalseContent: ToolbarContent>: ToolbarContent, _ToolbarContentPrimitive {
    case trueContent(TrueContent)
    case falseContent(FalseContent)

    public typealias Body = Never
    public var body: Never { fatalError("Conditional toolbar content is primitive") }

    fileprivate var _toolbarItems: [AnyToolbarItem] {
        switch self {
        case .trueContent(let content): return flattenToolbarContent(content)
        case .falseContent(let content): return flattenToolbarContent(content)
        }
    }
}

/// A single toolbar item with placement and content.
public struct ToolbarItem<Content: View>: ToolbarContent, _ToolbarContentPrimitive {
    public typealias Body = Never

    public let placement: ToolbarItemPlacement
    public let content: Content

    public init(placement: ToolbarItemPlacement = .primaryAction,
                @ViewBuilder content: () -> Content) {
        self.placement = placement
        self.content = content()
    }

    public var body: Never { fatalError("ToolbarItem is a primitive toolbar content") }

    fileprivate var _toolbarItems: [AnyToolbarItem] { [AnyToolbarItem(self)] }
}

/// A group of related toolbar controls that share a placement.
///
/// This mirrors SwiftUI's `ToolbarItemGroup`: its contents are presented as
/// one native toolbar group, which lets a platform preserve its own spacing
/// and focus behavior between the controls.
public struct ToolbarItemGroup<Content: View>: ToolbarContent, _ToolbarContentPrimitive {
    public typealias Body = Never
    public let placement: ToolbarItemPlacement
    public let content: Content

    public init(
        placement: ToolbarItemPlacement = .automatic,
        @ViewBuilder content: () -> Content
    ) {
        self.placement = placement
        self.content = content()
    }

    public var body: Never { fatalError("ToolbarItemGroup is a primitive toolbar content") }

    fileprivate var _toolbarItems: [AnyToolbarItem] {
        [AnyToolbarItem(placement: placement, wrapped: content)]
    }
}

/// Type-erased toolbar item.
public struct AnyToolbarItem {
    public let placement: ToolbarItemPlacement
    public let wrapped: any View

    public init<Content: View>(_ item: ToolbarItem<Content>) {
        self.placement = item.placement
        self.wrapped = item.content
    }

    init<Content: View>(placement: ToolbarItemPlacement, wrapped: Content) {
        self.placement = placement
        self.wrapped = wrapped
    }
}

/// Protocol for views that carry toolbar items (for NavigationStack extraction).
public protocol ToolbarProvider {
    var toolbarItems: [AnyToolbarItem] { get }
}

/// Protocol for views that carry toolbar configuration.
public protocol ToolbarConfigurationProvider {
    var toolbarConfiguration: ToolbarConfiguration { get }
}

/// A view that carries toolbar items alongside its content.
public struct ToolbarView<Content: View>: View, ToolbarProvider, ToolbarConfigurationProvider {
    public typealias Body = Never

    public let content: Content
    public let toolbarID: String?
    public let toolbarItems: [AnyToolbarItem]
    public let toolbarConfiguration: ToolbarConfiguration

    public var body: Never { fatalError("ToolbarView is a primitive view") }
}

/// A view wrapper that carries toolbar visibility/removal configuration.
public struct ToolbarConfigurationView<Content: View>: View, PrimitiveView, ToolbarConfigurationProvider {
    public typealias Body = Never

    public let content: Content
    public let toolbarConfiguration: ToolbarConfiguration

    public var body: Never { fatalError("ToolbarConfigurationView is a primitive view") }
}

private func mergeRemovedPlacements(
    existing: [ToolbarItemPlacement],
    incoming: [ToolbarItemPlacement]
) -> [ToolbarItemPlacement] {
    existing + incoming.filter { !existing.contains($0) }
}

extension View {
    /// Adds one or more toolbar items.
    public func toolbar<Content: ToolbarContent>(
        @ToolbarContentBuilder content: () -> Content
    ) -> ToolbarView<Self> {
        let toolbarContent = content()
        return ToolbarView(
            content: self,
            toolbarID: nil,
            toolbarItems: flattenToolbarContent(toolbarContent),
            toolbarConfiguration: ToolbarConfiguration()
        )
    }

    /// Adds one or more toolbar items with a stored toolbar identifier.
    public func toolbar<Content: ToolbarContent>(
        id: String,
        @ToolbarContentBuilder content: () -> Content
    ) -> ToolbarView<Self> {
        let toolbarContent = content()
        return ToolbarView(
            content: self,
            toolbarID: id,
            toolbarItems: flattenToolbarContent(toolbarContent),
            toolbarConfiguration: ToolbarConfiguration()
        )
    }

    /// Stores toolbar visibility for a target container.
    public func toolbar(
        _ visibility: ToolbarVisibility,
        for target: ToolbarPlacementTarget
    ) -> ToolbarConfigurationView<Self> {
        ToolbarConfigurationView(
            content: self,
            toolbarConfiguration: ToolbarConfiguration(
                visibility: visibility,
                visibilityTarget: target
            )
        )
    }

    /// Stores item placements that should be removed from the toolbar.
    public func toolbar(
        removing placements: ToolbarItemPlacement...
    ) -> ToolbarConfigurationView<Self> {
        ToolbarConfigurationView(
            content: self,
            toolbarConfiguration: ToolbarConfiguration(
                removedPlacements: placements
            )
        )
    }
}

extension ToolbarConfigurationView {
    /// Adds one or more toolbar items while preserving stored toolbar configuration.
    public func toolbar<ToolbarItems: ToolbarContent>(
        @ToolbarContentBuilder content: () -> ToolbarItems
    ) -> ToolbarView<Content> {
        let toolbarContent = content()
        return ToolbarView(
            content: self.content,
            toolbarID: nil,
            toolbarItems: flattenToolbarContent(toolbarContent),
            toolbarConfiguration: toolbarConfiguration
        )
    }

    /// Adds one or more toolbar items with a stored identifier while preserving toolbar configuration.
    public func toolbar<ToolbarItems: ToolbarContent>(
        id: String,
        @ToolbarContentBuilder content: () -> ToolbarItems
    ) -> ToolbarView<Content> {
        let toolbarContent = content()
        return ToolbarView(
            content: self.content,
            toolbarID: id,
            toolbarItems: flattenToolbarContent(toolbarContent),
            toolbarConfiguration: toolbarConfiguration
        )
    }

    /// Updates toolbar visibility while preserving other stored toolbar configuration.
    public func toolbar(
        _ visibility: ToolbarVisibility,
        for target: ToolbarPlacementTarget
    ) -> ToolbarConfigurationView<Content> {
        ToolbarConfigurationView(
            content: content,
            toolbarConfiguration: ToolbarConfiguration(
                visibility: visibility,
                visibilityTarget: target,
                removedPlacements: toolbarConfiguration.removedPlacements
            )
        )
    }

    /// Adds removed placements while preserving stored toolbar visibility.
    public func toolbar(
        removing placements: ToolbarItemPlacement...
    ) -> ToolbarConfigurationView<Content> {
        ToolbarConfigurationView(
            content: content,
            toolbarConfiguration: ToolbarConfiguration(
                visibility: toolbarConfiguration.visibility,
                visibilityTarget: toolbarConfiguration.visibilityTarget,
                removedPlacements: mergeRemovedPlacements(
                    existing: toolbarConfiguration.removedPlacements,
                    incoming: placements
                )
            )
        )
    }
}

extension ToolbarView {
    /// Adds one or more toolbar items while preserving existing items and configuration.
    public func toolbar<ToolbarItems: ToolbarContent>(
        @ToolbarContentBuilder content: () -> ToolbarItems
    ) -> ToolbarView<Content> {
        let toolbarContent = content()
        return ToolbarView(
            content: self.content,
            toolbarID: toolbarID,
            toolbarItems: toolbarItems + flattenToolbarContent(toolbarContent),
            toolbarConfiguration: toolbarConfiguration
        )
    }

    /// Adds one or more toolbar items with a stored identifier while preserving configuration.
    public func toolbar<ToolbarItems: ToolbarContent>(
        id: String,
        @ToolbarContentBuilder content: () -> ToolbarItems
    ) -> ToolbarView<Content> {
        let toolbarContent = content()
        return ToolbarView(
            content: self.content,
            toolbarID: id,
            toolbarItems: toolbarItems + flattenToolbarContent(toolbarContent),
            toolbarConfiguration: toolbarConfiguration
        )
    }

    /// Updates toolbar visibility while preserving stored items and toolbar configuration.
    public func toolbar(
        _ visibility: ToolbarVisibility,
        for target: ToolbarPlacementTarget
    ) -> ToolbarView<Content> {
        ToolbarView(
            content: content,
            toolbarID: toolbarID,
            toolbarItems: toolbarItems,
            toolbarConfiguration: ToolbarConfiguration(
                visibility: visibility,
                visibilityTarget: target,
                removedPlacements: toolbarConfiguration.removedPlacements
            )
        )
    }

    /// Adds removed placements while preserving stored items and toolbar configuration.
    public func toolbar(
        removing placements: ToolbarItemPlacement...
    ) -> ToolbarView<Content> {
        ToolbarView(
            content: content,
            toolbarID: toolbarID,
            toolbarItems: toolbarItems,
            toolbarConfiguration: ToolbarConfiguration(
                visibility: toolbarConfiguration.visibility,
                visibilityTarget: toolbarConfiguration.visibilityTarget,
                removedPlacements: mergeRemovedPlacements(
                    existing: toolbarConfiguration.removedPlacements,
                    incoming: placements
                )
            )
        )
    }
}
