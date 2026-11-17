import Foundation

/// A control that copies `value` to the clipboard when activated, then
/// briefly confirms it in place of its label. Same API as the SwiftUI
/// backend's; copies through the backend's clipboard service.
public struct CopyButton<L: View>: View {
    let value: String
    let label: L
    @State private var copied = false
    @State private var feedbackID = UUID()

    public init(_ value: String, @ViewBuilder label: () -> L) {
        self.value = value
        self.label = label()
    }

    public var body: some View {
        let value = value
        return Button {
            SystemServices.copyToClipboard(value)
            copied = true
            let id = UUID()
            feedbackID = id
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                if feedbackID == id { copied = false }
            }
        } label: {
            if copied {
                Label("Copied", systemImage: "checkmark")
            } else {
                label
            }
        }
    }
}
