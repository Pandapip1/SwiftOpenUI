import Foundation

// SwiftUI-shaped initializers and modifiers for existing controls.

// MARK: - Task with id

/// `.task(id:)` — runs the action when the view appears and again whenever `id` changes, cancelling the previous run.
/// Same parity notes as `TaskModifierView`: runs are tied to the view host, not to the view's lifetime.
public struct TaskIDModifierView<Content: View, ID: Equatable & Sendable>: View {
    let content: Content
    let id: ID
    let priority: TaskPriority
    let action: @MainActor @Sendable () async -> Void
    @State private var runner = TaskRunner()

    public var body: some View {
        let runner = _runner.storage.value
        let current = id
        let priority = priority
        let action = action
        return content
            .onAppear { runner.startIfNeeded(id: current) { Task(priority: priority) { await action() } } }
            .onChange(of: current) { _ in runner.restart(id: current) { Task(priority: priority) { await action() } } }
    }
}

final class TaskRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var lastID: AnyHashable?
    private var running: Task<Void, Never>?

    func startIfNeeded<ID: Equatable>(id: ID, start: () -> Task<Void, Never>) {
        lock.lock(); defer { lock.unlock() }
        guard lastID == nil else { return }
        lastID = AnyHashable(EquatableBox(id))
        running = start()
    }

    func restart<ID: Equatable>(id: ID, start: () -> Task<Void, Never>) {
        lock.lock(); defer { lock.unlock() }
        let box = AnyHashable(EquatableBox(id))
        guard lastID != box else { return }
        lastID = box
        running?.cancel()
        running = start()
    }
}

/// Lets any `Equatable` be compared through `AnyHashable`.
private struct EquatableBox<V: Equatable>: Hashable {
    let value: V
    init(_ value: V) { self.value = value }
    static func == (l: Self, r: Self) -> Bool { l.value == r.value }
    func hash(into hasher: inout Hasher) { hasher.combine(0) }
}

extension View {
    public func task<ID: Equatable & Sendable>(
        id: ID,
        priority: TaskPriority = .userInitiated,
        _ action: @escaping @MainActor @Sendable () async -> Void
    ) -> TaskIDModifierView<Self, ID> {
        TaskIDModifierView(content: self, id: id, priority: priority, action: action)
    }
}

// MARK: - Picker styles

extension PickerStyle {
    /// A pop-up menu is what the default style already renders.
    public static var menu: PickerStyle { .automatic }
    public static var inline: PickerStyle { .automatic }
    public static var wheel: PickerStyle { .automatic }
    public static var navigationLink: PickerStyle { .automatic }
}

// MARK: - Colors

extension Color {
    /// The accent color used for controls.
    public static let accentColor = Color(red: 0.0, green: 0.478, blue: 1.0)
}

// MARK: - Section with view header/footer

extension Section {
    public init<F: View>(footer: F, @ViewBuilder content: () -> Content) {
        self.init(header: nil, footer: Self.text(of: footer), content: content)
    }

    public init<H: View, F: View>(header: H, footer: F, @ViewBuilder content: () -> Content) {
        self.init(header: Self.text(of: header), footer: Self.text(of: footer), content: content)
    }

    public init<H: View>(header: H, @ViewBuilder content: () -> Content) {
        self.init(header: Self.text(of: header), footer: nil, content: content)
    }

    private static func text(of view: any View) -> String {
        AlertActions.flatten(view).compactMap { ($0 as? Text)?.content }.joined(separator: "\n")
    }
}

// MARK: - ScrollView indicators

extension ScrollView {
    public init(_ axes: Axis = .vertical, showsIndicators: Bool, @ViewBuilder content: () -> Content) {
        self.init(axes, content: content)
    }
}

// MARK: - Toggle with a view label

extension Toggle {
    /// `Toggle(isOn: $flag) { Text("…") }`. The label's text becomes the toggle's title.
    public init<L: View>(isOn: Binding<Bool>, @ViewBuilder label: () -> L) {
        let title = AlertActions.flatten(label()).compactMap { v -> String? in
            if let t = v as? Text { return t.content }
            if let l = v as? SwiftOpenUI.Label { return l.title }
            return nil
        }.joined(separator: " ")
        self.init(title, isOn: isOn)
    }
}

// MARK: - Toolbar content from plain views

extension ToolbarContentBuilder {
    /// A bare `Button` (or any view) in a toolbar becomes an item in the default placement.
    public static func buildExpression<V: View>(_ expression: V) -> ToolbarContent {
        ToolbarContent(items: [AnyToolbarItem(ToolbarItem(placement: .primaryAction) { expression })])
    }
}

// MARK: - Editing affordances (no-ops where there is no edit mode)

extension ForEach {
    /// Accepted for source compatibility; swipe-to-delete has no desktop equivalent here.
    public func onDelete(perform action: ((IndexSet) -> Void)?) -> ForEach { self }
    /// Accepted for source compatibility; drag-to-reorder is not rendered.
    public func onMove(perform action: ((IndexSet, Int) -> Void)?) -> ForEach { self }
}

/// SwiftUI's EditButton. There is no list edit mode, so it renders nothing.
public struct EditButton: View {
    public init() {}
    public var body: some View { EmptyView() }
}

extension URL {
    /// Security-scoped access only exists on Apple sandboxes; elsewhere the URL is directly readable.
    public func startAccessingSecurityScopedResource() -> Bool { false }
    public func stopAccessingSecurityScopedResource() {}
}

extension Link {
    public init(_ title: String, destination: URL) { self.init(title, destination: destination.absoluteString) }
}
