import Foundation

// Controls and modifiers named for the behaviour an application wants, so the
// application states it once and each backend decides how its platform
// provides it. The SwiftUI backend has the same API
// (Sources/Backend/SwiftUI/AdaptiveControls.swift); these are the portable
// backends' versions: desktop windows, a mouse and keyboard, no edit mode, no
// software keyboard, and stacks that build every row up front.

// MARK: - Links and stacks

/// Opens `destination` in the user's default handler (usually the web
/// browser) when activated.
public struct ExternalURLLink<Label: View>: View {
    private let destination: URL
    private let label: () -> Label

    public init(destination: URL, @ViewBuilder label: @escaping () -> Label) {
        self.destination = destination
        self.label = label
    }

    public var body: some View {
        let destination = destination
        return Button { SystemServices.openURL(destination) } label: { label() }
    }
}

/// A vertical stack for long content. Backends that realize rows lazily do
/// so; these backends build every row up front.
public struct LazyContentStack<Content: View>: View {
    private let alignment: HorizontalAlignment
    private let spacing: CGFloat?
    private let content: () -> Content

    public init(alignment: HorizontalAlignment = .center, spacing: CGFloat? = nil,
                @ViewBuilder content: @escaping () -> Content) {
        self.alignment = alignment
        self.spacing = spacing
        self.content = content
    }

    public var body: some View {
        VStack(alignment: alignment, spacing: spacing ?? 8, content: content)
    }
}

// MARK: - Paged lists

extension View {
    /// Loads the next page of a long list when its last row appears. These
    /// backends build every row up front, so every row would "appear" at
    /// once; they offer `LoadNextPageButton` instead and this does nothing.
    public func loadsNextPageWhenLast(_ isLast: Bool, _ load: @escaping () async -> Void) -> some View {
        self
    }
}

/// An explicit "Load more" control for the next page of a long list, shown
/// where rows are not realized lazily (so `loadsNextPageWhenLast` cannot
/// load on scroll). These backends show it while `isAvailable`.
public struct LoadNextPageButton: View {
    private let isAvailable: Bool
    private let load: () -> Void

    public init(isAvailable: Bool, load: @escaping () -> Void) {
        self.isAvailable = isAvailable
        self.load = load
    }

    public var body: some View {
        if isAvailable {
            Button("Load more", action: load)
                .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Menus

/// One entry of an `AdaptiveActionMenu`.
public struct AdaptiveMenuItem<Value>: Identifiable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let value: Value

    public init(id: String, title: String, systemImage: String, value: Value) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.value = value
    }
}

/// A button showing `systemImage` that opens a menu of `items`; choosing one
/// calls `action` with its value and title. Each backend uses the menu its
/// platform's input handles well (on tvOS, the system's focus-driven menu).
public struct AdaptiveActionMenu<Value>: View {
    private let title: String
    private let systemImage: String
    private let items: [AdaptiveMenuItem<Value>]
    private let action: @MainActor @Sendable (Value, String) -> Void

    public init(title: String, systemImage: String, items: [AdaptiveMenuItem<Value>],
                action: @escaping @MainActor @Sendable (Value, String) -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.items = items
        self.action = action
    }

    public var body: some View {
        Menu {
            ForEach(items) { item in
                Button { action(item.value, item.title) } label: {
                    Label(item.title, systemImage: item.systemImage)
                }
            }
        } label: {
            Image(systemName: systemImage)
        }
        .accessibilityLabel(title)
    }
}

/// A dialog's standard keyboard shortcut: Return for the default action,
/// Escape for cancel.
public enum DialogShortcut: Sendable, Equatable {
    case defaultAction
    case cancelAction
}

// MARK: - Lists, navigation and text entry

extension View {
    /// Binds a dialog's standard shortcut where the platform has keyboard
    /// shortcuts (every desktop backend does).
    public func keyboardShortcutWhereAvailable(_ shortcut: DialogShortcut) -> some View {
        keyboardShortcut(shortcut == .defaultAction ? .defaultAction : .cancelAction)
    }

    /// Hides the separator below this list row, where lists draw them.
    public func hiddenListRowSeparator() -> some View {
        listRowSeparator(.hidden)
    }

    /// The title style for a pushed detail page: compact where navigation
    /// bars offer a large title (iOS). Desktop header bars have one style.
    public func detailNavigationStyle() -> some View {
        self
    }

    /// A destructive action on a list row: a swipe action where rows swipe;
    /// here, the row's context menu.
    public func destructiveRowAction(_ title: String, action: @escaping () -> Void) -> some View {
        swipeActions { Button(title, role: .destructive, action: action) }
    }

    /// A text field for entering a URL: no automatic capitalization and a
    /// URL keyboard where there is a software keyboard. Desktop keyboards
    /// have no variants.
    public func urlEntryStyle() -> some View {
        self
    }

    /// A text field in a settings form: a bordered field where forms draw
    /// them.
    public func settingsTextEntryStyle() -> some View {
        textFieldStyle(.roundedBorder)
    }

    /// Makes read-only text reachable where navigation is by focus alone
    /// (tvOS), so it can be scrolled to and read. Pointer-driven backends
    /// need nothing.
    public func focusableReadOnlyValue() -> some View {
        self
    }

    /// A video detail page whose player runs under the navigation bar to the
    /// top edge (iOS). Desktop windows keep their header bar.
    public func immersiveVideoDetailStyle() -> some View {
        self
    }
}

/// Chooses a whole number from `values`, where 0 is shown as `zeroLabel`:
/// a stepper with pointer input, a picker where a remote's focus moves
/// between choices (tvOS).
public struct RemoteFriendlyBoundedSelection: View {
    private let title: String
    private let value: Binding<Int>
    private let values: [Int]
    private let zeroLabel: String
    private let step: Int

    public init(title: String, value: Binding<Int>, values: [Int], zeroLabel: String, step: Int) {
        self.title = title
        self.value = value
        self.values = values
        self.zeroLabel = zeroLabel
        self.step = step
    }

    public var body: some View {
        let current = value.wrappedValue
        return Stepper("\(title): \(current == 0 ? zeroLabel.lowercased() : String(current))",
                       value: value, in: (values.min() ?? 0)...(values.max() ?? 0), step: step)
    }
}

// MARK: - Settings pages

/// The content of a settings detail page. Each backend lays it out the way
/// its settings windows expect.
public struct SettingsDetailContainer<Content: View>: View {
    private let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        content()
    }
}

// MARK: - Sharing and documents

/// Shares `item` with the platform's share mechanism (here, copying it to
/// the clipboard), or nothing while there is no item or where the platform
/// cannot share (tvOS).
public struct ShareContentAction<Label: View>: View {
    private let item: URL?
    private let label: () -> Label

    public init(item: URL?, @ViewBuilder label: @escaping () -> Label) {
        self.item = item
        self.label = label
    }

    public var body: some View {
        if let item { ShareLink(item: item, label: label) }
    }
}

/// A settings section that exports a document (once `exportURL` is ready)
/// and asks to import one. Nothing is shown where the platform has no
/// share sheet or file picker (tvOS).
public struct DocumentTransferControls: View {
    private let title: String
    private let exportURL: URL?
    private let exportLabel: String
    private let importLabel: String
    private let status: String?
    private let requestImport: () -> Void

    public init(title: String, exportURL: URL?, exportLabel: String, importLabel: String,
                status: String?, requestImport: @escaping () -> Void) {
        self.title = title
        self.exportURL = exportURL
        self.exportLabel = exportLabel
        self.importLabel = importLabel
        self.status = status
        self.requestImport = requestImport
    }

    public var body: some View {
        Section(title) {
            if let exportURL {
                ShareLink(item: exportURL) { Label(exportLabel, systemImage: "square.and.arrow.up") }
            } else {
                Label("Preparing export…", systemImage: "square.and.arrow.up")
                    .foregroundStyle(.secondary)
            }
            Button(action: requestImport) {
                Label(importLabel, systemImage: "square.and.arrow.down")
            }
            if let status {
                Text(status).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

extension View {
    /// Asks for a JSON document while `isPresented` is true and calls
    /// `onImport` with the chosen file. Nothing is presented where the
    /// platform has no file picker (tvOS).
    public func jsonDocumentImporter(isPresented: Binding<Bool>, onImport: @escaping (URL) -> Void) -> some View {
        fileImporter(isPresented: isPresented, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            onImport(url)
        }
    }

    /// Prepares the document `DocumentTransferControls` exports whenever
    /// `id` changes. Nothing is prepared where nothing can be exported
    /// (tvOS).
    public func preparesDocumentExport(id: String, _ prepare: @escaping @Sendable () async -> Void) -> some View {
        task(id: id, prepare)
    }
}

// MARK: - Full-screen video

extension View {
    /// Presents `content` (a video player) full screen while `isPresented`
    /// is true, and sets it false when the user leaves full screen. Here, a
    /// full-screen cover.
    public func videoFullscreenPresentation<Content: View>(
        isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        fullScreenCover(isPresented: isPresented, content: content)
    }
}

// MARK: - Diagnostics

/// What has keyboard or remote focus, for debugger output.
public enum FocusDiagnostics {
    /// A description of the focused item where the platform has a focus
    /// engine that reports one (tvOS); nil here.
    @MainActor
    public static func focusedItemDescription() -> String? { nil }
}

/// A titled section the viewer expands and collapses (collapsed at first).
/// Same API as the SwiftUI backend; here a disclosure group.
public struct CollapsibleSection<Content: View>: View {
    private let title: String
    private let content: Content
    @State private var expanded = false

    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        DisclosureGroup(title, isExpanded: $expanded) { content }
    }
}
