import SwiftUI

enum LLMSwitchIconButtonStyle {
    case plain
    case borderless
}

struct LLMSwitchIconButton: View {
    @EnvironmentObject private var toastCenter: LLMSwitchToastCenter

    let systemName: String
    let helpText: String
    let role: ButtonRole?
    let isDisabled: Bool
    let style: LLMSwitchIconButtonStyle
    let toastMessage: String?
    let action: () -> Void

    init(
        _ systemName: String,
        help: String,
        role: ButtonRole? = nil,
        isDisabled: Bool = false,
        style: LLMSwitchIconButtonStyle = .borderless,
        toastMessage: String? = nil,
        action: @escaping () -> Void
    ) {
        self.systemName = systemName
        self.helpText = help
        self.role = role
        self.isDisabled = isDisabled
        self.style = style
        self.toastMessage = toastMessage
        self.action = action
    }

    var body: some View {
        if style == .plain {
            button
                .buttonStyle(.plain)
        } else {
            button
                .buttonStyle(.borderless)
        }
    }

    private var button: some View {
        Button(role: role, action: handleTap) {
            Image(systemName: systemName)
                .frame(width: 16, height: 16)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .help(helpText)
        .accessibilityLabel(helpText)
        .disabled(isDisabled)
        .focusable(false)
        .llmSwitchPointingHandCursor()
    }

    private func handleTap() {
        action()
        if let toastMessage, !toastMessage.isEmpty {
            toastCenter.show(toastMessage)
        }
    }
}
