/// Projects `Binding<T>` values from an `@Observable` class's
/// mutable properties, matching SwiftUI's `@Bindable` property
/// wrapper introduced alongside the Observation framework.
///
/// Typical usage — a view owns an `@Observable` via
/// `@Environment(SomeClass.self)` and needs bindings for controls
/// like `TextField`:
///
/// ```swift
/// struct ContentView: View {
///     @Environment(AppState.self) var appState
///     var body: some View {
///         @Bindable var appState = appState
///         TextField("Name", text: $appState.name)
///     }
/// }
/// ```
///
/// The wrapper itself carries the object reference; `$`-prefix
/// accesses (`$appState.name`) hit the `@dynamicMemberLookup`
/// subscript, which builds a `Binding<T>` whose get/set close over
/// the underlying `ReferenceWritableKeyPath`.
///
/// Reactivity comes from the same path as a plain `@Environment`
/// read — projecting the binding reads the property while body is evaluated
/// inside `withObservationTracking`. Rendering the control can then happen
/// outside that scope without losing the dependency.
@propertyWrapper
@dynamicMemberLookup
public struct Bindable<Value: AnyObject> {
    public var wrappedValue: Value

    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }

    /// `$bindable` returns the `Bindable` itself so that
    /// `$bindable.property` triggers the dynamic-member subscript.
    public var projectedValue: Bindable<Value> { self }

    /// Project a `Binding<T>` to a mutable property of the wrapped
    /// object. Reads and writes both go through the object's own
    /// storage via the keypath, so they participate in the normal
    /// Observation / rebuild cycle.
    public subscript<T>(
        dynamicMember keyPath: ReferenceWritableKeyPath<Value, T>
    ) -> Binding<T> {
        let object = wrappedValue
        // Register this dependency while the owning body is being evaluated.
        // The native control may not read its binding until rendering, after
        // the body's observation scope has ended. Keep the getter live below;
        // this read registers observation, it does not snapshot the value.
        _ = object[keyPath: keyPath]
        return Binding(
            get: { object[keyPath: keyPath] },
            set: { object[keyPath: keyPath] = $0 }
        )
    }
}
