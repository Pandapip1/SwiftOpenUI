import Foundation

/// The coordinate space in which a location is expressed.
public enum CoordinateSpace: Hashable {
    case global
    case local
    case named(AnyHashable)
}

/// A frame of reference within the layout system.
public protocol CoordinateSpaceProtocol {
    var coordinateSpace: CoordinateSpace { get }
}

public struct GlobalCoordinateSpace: CoordinateSpaceProtocol, Hashable, Sendable {
    public var coordinateSpace: CoordinateSpace { .global }
    public init() {}
}

public struct LocalCoordinateSpace: CoordinateSpaceProtocol, Hashable, Sendable {
    public var coordinateSpace: CoordinateSpace { .local }
    public init() {}
}

public struct NamedCoordinateSpace: CoordinateSpaceProtocol, Hashable {
    public let name: AnyHashable
    public var coordinateSpace: CoordinateSpace { .named(name) }
    public init(name: AnyHashable) { self.name = name }
}

extension CoordinateSpaceProtocol where Self == GlobalCoordinateSpace {
    public static var global: GlobalCoordinateSpace { GlobalCoordinateSpace() }
}

extension CoordinateSpaceProtocol where Self == LocalCoordinateSpace {
    public static var local: LocalCoordinateSpace { LocalCoordinateSpace() }
}

extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
    public static func named(_ name: some Hashable) -> NamedCoordinateSpace {
        NamedCoordinateSpace(name: AnyHashable(name))
    }
}

/// The current phase of a continuous pointer hover interaction.
public enum HoverPhase: Equatable, Sendable {
    case active(CGPoint)
    case ended
}

/// Backend storage for the public opaque continuous-hover modifier.
@_spi(SwiftOpenUIBackend)
public struct _ContinuousHoverView<Content: View>: View {
    public typealias Body = Never

    @_spi(SwiftOpenUIBackend) public let content: Content
    @_spi(SwiftOpenUIBackend) public let coordinateSpace: CoordinateSpace
    @_spi(SwiftOpenUIBackend) public let action: (HoverPhase) -> Void

    @_spi(SwiftOpenUIBackend)
    public init(content: Content, coordinateSpace: CoordinateSpace,
                action: @escaping (HoverPhase) -> Void) {
        self.content = content
        self.coordinateSpace = coordinateSpace
        self.action = action
    }

    public var body: Never { fatalError("ContinuousHoverView is a primitive view") }
}

@_spi(SwiftOpenUIBackend)
public struct _CoordinateSpaceView<Content: View>: View {
    public typealias Body = Never
    @_spi(SwiftOpenUIBackend) public let content: Content
    @_spi(SwiftOpenUIBackend) public let name: AnyHashable
    @_spi(SwiftOpenUIBackend)
    public init(content: Content, name: AnyHashable) { self.content = content; self.name = name }
    public var body: Never { fatalError("_CoordinateSpaceView is a primitive view") }
}

/// A view that recognizes tap gestures on its content.
public struct TapGestureView<Content: View>: View {
    public typealias Body = Never

    public let content: Content
    public let count: Int
    public let action: () -> Void

    public var body: Never { fatalError("TapGestureView is a primitive view") }
}

/// A view that recognizes long-press gestures on its content.
public struct LongPressGestureView<Content: View>: View {
    public typealias Body = Never

    public let content: Content
    public let minimumDuration: Double
    public let action: () -> Void

    public var body: Never { fatalError("LongPressGestureView is a primitive view") }
}

/// Value describing a drag gesture's current state.
public struct DragGestureValue {
    /// The location where the drag started.
    public let startLocation: (x: Double, y: Double)
    /// The current location of the drag.
    public let location: (x: Double, y: Double)
    /// The total translation from the start.
    public let translation: (width: Double, height: Double)

    /// Convenience: translation width (matches SwiftUI CGSize.width).
    public var width: Double { translation.width }
    /// Convenience: translation height (matches SwiftUI CGSize.height).
    public var height: Double { translation.height }

    public init(startLocation: (x: Double, y: Double), location: (x: Double, y: Double), translation: (width: Double, height: Double)) {
        self.startLocation = startLocation
        self.location = location
        self.translation = translation
    }
}

/// A view that recognizes drag gestures on its content.
public struct DragGestureView<Content: View>: View {
    public typealias Body = Never

    public let content: Content
    public let minimumDistance: Double
    public let onChanged: ((DragGestureValue) -> Void)?
    public let onEnded: ((DragGestureValue) -> Void)?

    public var body: Never { fatalError("DragGestureView is a primitive view") }
}

extension View {
    /// Calls `action` whenever a pointing device moves over this view, and
    /// once more when it leaves the view.
    public func onContinuousHover(
        coordinateSpace: some CoordinateSpaceProtocol = .local,
        perform action: @escaping (HoverPhase) -> Void
    ) -> some View {
        _ContinuousHoverView(content: self, coordinateSpace: coordinateSpace.coordinateSpace, action: action)
    }

    public func coordinateSpace(name: some Hashable) -> some View {
        _CoordinateSpaceView(content: self, name: AnyHashable(name))
    }

    public func coordinateSpace(_ name: NamedCoordinateSpace) -> some View {
        _CoordinateSpaceView(content: self, name: name.name)
    }

    /// Attach a tap gesture recognizer to this view.
    public func onTapGesture(count: Int = 1, perform action: @escaping () -> Void) -> TapGestureView<Self> {
        TapGestureView(content: self, count: count, action: action)
    }

    /// Attach a long-press gesture recognizer to this view.
    public func onLongPressGesture(minimumDuration: Double = 0.5, perform action: @escaping () -> Void) -> LongPressGestureView<Self> {
        LongPressGestureView(content: self, minimumDuration: minimumDuration, action: action)
    }

    /// Attach a drag gesture recognizer to this view.
    public func onDrag(
        minimumDistance: Double = 10,
        onChanged: ((DragGestureValue) -> Void)? = nil,
        onEnded: ((DragGestureValue) -> Void)? = nil
    ) -> DragGestureView<Self> {
        DragGestureView(content: self, minimumDistance: minimumDistance, onChanged: onChanged, onEnded: onEnded)
    }

    /// Trailing-closure convenience: attach a drag gesture with an onChanged handler.
    public func onDrag(
        minimumDistance: Double = 10,
        _ handler: @escaping (DragGestureValue) -> Void
    ) -> DragGestureView<Self> {
        DragGestureView(content: self, minimumDistance: minimumDistance, onChanged: handler, onEnded: nil)
    }

    /// Defines the view's hit-testing shape, most commonly so a view with no
    /// visible fill (`Color.clear`, an empty `Rectangle`) still receives taps
    /// across its full frame rather than only where something is painted.
    ///
    /// Every current backend already hit-tests gestures against a view's
    /// full allocated frame regardless of what it paints, so there is no
    /// transparent-background gap for `shape` to patch here — this is a
    /// no-op passthrough kept only so call sites written against SwiftUI's
    /// real API compile unchanged. If a backend ever hit-tests by painted
    /// content instead, give this its own `_ContentShapeView` and read
    /// `shape`/`eoFill` there.
    public func contentShape<S: Shape>(_ shape: S, eoFill: Bool = false) -> Self {
        self
    }
}
