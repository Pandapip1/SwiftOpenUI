import Foundation

// SwiftUI-shaped `alert` and `confirmationDialog` overloads whose buttons are written as `Button` views.
// They are read back into the `[AlertButton]` model the backends already render, so no backend change is needed.
// Limitation: alerts cannot host a `TextField` (the native dialogs on every backend have no input row).

private func messageText(_ view: any View) -> String {
    AlertActions.flatten(view).compactMap { ($0 as? Text)?.content }.joined(separator: "\n")
}

private func resolvedButtons(_ view: any View) -> [AlertButton] {
    let b = AlertActions.buttons(from: view)
    return b.isEmpty ? [AlertButton("OK")] : b
}

extension View {
    public func alert<A: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: () -> A
    ) -> AlertModifierView<Self> {
        alert(title, isPresented: isPresented, message: "", actions: resolvedButtons(actions()))
    }

    public func alert<A: View, M: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        @ViewBuilder actions: () -> A,
        @ViewBuilder message: () -> M
    ) -> AlertModifierView<Self> {
        alert(title, isPresented: isPresented, message: messageText(message()), actions: resolvedButtons(actions()))
    }

    public func alert<A: View, T>(
        _ title: String,
        isPresented: Binding<Bool>,
        presenting data: T?,
        @ViewBuilder actions: (T) -> A
    ) -> AlertModifierView<Self> {
        let buttons = data.map { resolvedButtons(actions($0)) } ?? [AlertButton("OK")]
        return alert(title, isPresented: isPresented, message: "", actions: buttons)
    }

    public func alert<A: View, M: View, T>(
        _ title: String,
        isPresented: Binding<Bool>,
        presenting data: T?,
        @ViewBuilder actions: (T) -> A,
        @ViewBuilder message: (T) -> M
    ) -> AlertModifierView<Self> {
        let buttons = data.map { resolvedButtons(actions($0)) } ?? [AlertButton("OK")]
        let text = data.map { messageText(message($0)) } ?? ""
        return alert(title, isPresented: isPresented, message: text, actions: buttons)
    }

    public func confirmationDialog<A: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic,
        @ViewBuilder actions: () -> A
    ) -> ConfirmationDialogView<Self> {
        confirmationDialog(title, isPresented: isPresented, titleVisibility: titleVisibility, actions: AlertActions.buttons(from: actions()))
    }

    public func confirmationDialog<A: View, M: View>(
        _ title: String,
        isPresented: Binding<Bool>,
        titleVisibility: Visibility = .automatic,
        @ViewBuilder actions: () -> A,
        @ViewBuilder message: () -> M
    ) -> ConfirmationDialogView<Self> {
        confirmationDialog(title, isPresented: isPresented, titleVisibility: titleVisibility,
                           actions: AlertActions.buttons(from: actions()), message: messageText(message()))
    }
}
