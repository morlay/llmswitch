import SwiftUI

struct CopyBaseURLIconButton: View {
    let isDisabled: Bool
    let toastMessage: String?
    let action: () -> Void

    init(isDisabled: Bool, toastMessage: String? = nil, action: @escaping () -> Void) {
        self.isDisabled = isDisabled
        self.toastMessage = toastMessage
        self.action = action
    }

    var body: some View {
        LLMSwitchIconButton(
            "link",
            help: "Copy Base URL",
            isDisabled: isDisabled,
            toastMessage: toastMessage,
            action: action
        )
    }
}

struct CopyAPIKeyIconButton: View {
    let isDisabled: Bool
    let toastMessage: String?
    let action: () -> Void

    init(isDisabled: Bool, toastMessage: String? = nil, action: @escaping () -> Void) {
        self.isDisabled = isDisabled
        self.toastMessage = toastMessage
        self.action = action
    }

    var body: some View {
        LLMSwitchIconButton(
            "key.horizontal",
            help: "Copy API Key",
            isDisabled: isDisabled,
            toastMessage: toastMessage,
            action: action
        )
    }
}

struct QuitIconButton: View {
    let toastMessage: String?
    let action: () -> Void

    init(toastMessage: String? = nil, action: @escaping () -> Void) {
        self.toastMessage = toastMessage
        self.action = action
    }

    var body: some View {
        LLMSwitchIconButton(
            "power",
            help: "Quit",
            toastMessage: toastMessage,
            action: action
        )
    }
}

struct ToggleProxyIconButton: View {
    @Binding var isOn: Bool
    let isDisabled: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(.switch)
            .labelsHidden()
            .fixedSize()
            .help(isOn ? "Stop Proxy" : "Start Proxy")
            .accessibilityLabel(isOn ? "Stop Proxy" : "Start Proxy")
            .disabled(isDisabled)
    }
}

struct RestartProxyIconButton: View {
    let isDisabled: Bool
    let toastMessage: String?
    let action: () -> Void

    init(isDisabled: Bool, toastMessage: String? = nil, action: @escaping () -> Void) {
        self.isDisabled = isDisabled
        self.toastMessage = toastMessage
        self.action = action
    }

    var body: some View {
        LLMSwitchIconButton(
            "arrow.clockwise.circle",
            help: "Restart Proxy",
            isDisabled: isDisabled,
            toastMessage: toastMessage,
            action: action
        )
    }
}

struct ReloadConfigIconButton: View {
    let isDisabled: Bool
    let toastMessage: String?
    let action: () -> Void

    init(isDisabled: Bool, toastMessage: String? = nil, action: @escaping () -> Void) {
        self.isDisabled = isDisabled
        self.toastMessage = toastMessage
        self.action = action
    }

    var body: some View {
        LLMSwitchIconButton(
            "arrow.clockwise",
            help: "Reload Config",
            isDisabled: isDisabled,
            toastMessage: toastMessage,
            action: action
        )
    }
}

struct OpenProvidersIconButton: View {
    let toastMessage: String?
    let action: () -> Void

    init(toastMessage: String? = nil, action: @escaping () -> Void) {
        self.toastMessage = toastMessage
        self.action = action
    }

    var body: some View {
        LLMSwitchIconButton(
            "gearshape",
            help: "Open Providers",
            toastMessage: toastMessage,
            action: action
        )
    }
}

struct AddProviderIconButton: View {
    let toastMessage: String?
    let action: () -> Void

    init(toastMessage: String? = nil, action: @escaping () -> Void) {
        self.toastMessage = toastMessage
        self.action = action
    }

    var body: some View {
        LLMSwitchIconButton(
            "plus",
            help: "Add Provider",
            style: .borderless,
            toastMessage: toastMessage,
            action: action
        )
    }
}

struct EditProviderIconButton: View {
    let toastMessage: String?
    let action: () -> Void

    init(toastMessage: String? = nil, action: @escaping () -> Void) {
        self.toastMessage = toastMessage
        self.action = action
    }

    var body: some View {
        LLMSwitchIconButton(
            "square.and.pencil",
            help: "Edit Provider",
            style: .borderless,
            toastMessage: toastMessage,
            action: action
        )
    }
}

struct ToggleProviderEnabledIconButton: View {
    let isEnabled: Bool
    let isDisabled: Bool
    let toastMessage: String?
    let action: () -> Void

    init(
        isEnabled: Bool,
        isDisabled: Bool,
        toastMessage: String? = nil,
        action: @escaping () -> Void
    ) {
        self.isEnabled = isEnabled
        self.isDisabled = isDisabled
        self.toastMessage = toastMessage
        self.action = action
    }

    var body: some View {
        LLMSwitchIconButton(
            isEnabled ? "pause.circle" : "play.circle",
            help: isEnabled ? "Disable Provider" : "Enable Provider",
            isDisabled: isDisabled,
            style: .borderless,
            toastMessage: toastMessage,
            action: action
        )
    }
}

struct DeleteProviderIconButton: View {
    let toastMessage: String?
    let action: () -> Void

    init(toastMessage: String? = nil, action: @escaping () -> Void) {
        self.toastMessage = toastMessage
        self.action = action
    }

    var body: some View {
        LLMSwitchIconButton(
            "trash",
            help: "Delete Provider",
            role: .destructive,
            style: .borderless,
            toastMessage: toastMessage,
            action: action
        )
    }
}
