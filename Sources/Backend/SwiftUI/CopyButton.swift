#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A control that copies `value` to the clipboard when activated, then
/// briefly confirms it in place of its label. Same API on every backend.
public struct CopyButton<Label: View>: View {
    private let value: String
    private let label: Label
    @State private var copied = false
    @State private var feedbackID = UUID()

    public init(_ value: String, @ViewBuilder label: () -> Label) {
        self.value = value
        self.label = label()
    }

    public var body: some View {
        Button {
            Self.copy(value)
            copied = true
            let id = UUID()
            feedbackID = id
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                if feedbackID == id { copied = false }
            }
        } label: {
            ZStack {
                // Keep the label's size so confirming doesn't resize the control.
                label.opacity(copied ? 0 : 1)
                if copied { SwiftUI.Label("Copied", systemImage: "checkmark") }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(copied ? "Copied" : "Copy \(value)")
        .accessibilityHint("Copies to the clipboard")
    }

    @MainActor
    private static func copy(_ value: String) {
        #if os(iOS) || os(visionOS)
        UIPasteboard.general.string = value
        #elseif os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #endif
    }
}
#endif
