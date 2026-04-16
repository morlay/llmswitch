import AppKit
import SwiftUI

struct MenuBarPanelView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var toastCenter: LLMSwitchToastCenter
    @State private var proxySwitchValue = false
    @State private var isTogglingProxy = false
    @State private var isRestartingProxy = false
    @State private var isReloadingConfig = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LLMSwitchToolbar {
                QuitIconButton {
                    confirmQuit()
                }
                Text("LLM Switch")
                    .font(.headline)
                Spacer()
                ToggleProxyIconButton(isOn: proxySwitchBinding, isDisabled: isAnyProxyActionInFlight)
            }

            Divider()

            LLMSwitchToolbar {
                Text(model.isProxyRunning ? model.listenAddress : "")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                LLMSwitchToolbar {
                    CopyBaseURLIconButton(
                        isDisabled: !model.isProxyRunning || model.listenAddress.isEmpty,
                        toastMessage: "Base URL copied"
                    ) {
                        model.copyBaseURL()
                    }
                    CopyAPIKeyIconButton(isDisabled: model.serviceAPIKey.isEmpty, toastMessage: "API key copied") {
                        model.copyServiceAPIKey()
                    }
                    RestartProxyIconButton(isDisabled: !model.isProxyRunning || isAnyProxyActionInFlight) {
                        Task {
                            await restartProxy()
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                LLMSwitchToolbar {
                    Text("Providers")
                        .font(.caption.weight(.medium))
                    Spacer()
                    ReloadConfigIconButton(isDisabled: isAnyProxyActionInFlight) {
                        Task {
                            await reloadConfig()
                        }
                    }
                    OpenProvidersIconButton {
                        openProvidersWindow()
                    }
                }

                let enabledProviders = model.providerStatuses.filter(\.isEnabled)
                VStack(alignment: .leading, spacing: 4) {
                    if enabledProviders.isEmpty {
                        Text("No enabled providers")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(enabledProviders.prefix(8)) { provider in
                        LLMSwitchListItem {
                            Text(provider.providerName)
                            Spacer()
                            LLMSwitchStatusDot(state: provider.healthState)
                        }
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                LLMSwitchToolbar {
                    Text("Models")
                        .font(.caption.weight(.medium))
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 4) {
                    if model.modelSwitchRows.isEmpty {
                        Text("No models")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(model.modelSwitchRows.prefix(8)) { row in
                        LLMSwitchListItem {
                            Text(row.publicName)
                            Spacer()
                            modelSelectionMenu(for: row)
                        }
                    }
                }
            }

        }
        .frame(width: 280)
        .padding(12)
        .overlay(alignment: .bottom) {
            LLMSwitchToastOverlay()
                .padding(.bottom, 4)
        }
        .background {
            LLMSwitchOutlineSuppressor()
        }
        .task {
            await model.bootstrap()
        }
        .onAppear {
            proxySwitchValue = model.isProxyRunning
        }
        .onChange(of: model.isProxyRunning) { _, isRunning in
            proxySwitchValue = isRunning
        }
    }

    private var isAnyProxyActionInFlight: Bool {
        isTogglingProxy || isRestartingProxy || isReloadingConfig
    }

    private var proxySwitchBinding: Binding<Bool> {
        Binding(
            get: {
                isTogglingProxy ? proxySwitchValue : model.isProxyRunning
            },
            set: { shouldRun in
                guard !isAnyProxyActionInFlight else {
                    return
                }

                proxySwitchValue = shouldRun
                Task {
                    await toggleProxy(to: shouldRun)
                }
            }
        )
    }

    private func toggleProxy(to shouldRun: Bool) async {
        guard !isAnyProxyActionInFlight else {
            return
        }

        isTogglingProxy = true
        defer {
            isTogglingProxy = false
            proxySwitchValue = model.isProxyRunning
        }

        guard shouldRun != model.isProxyRunning else {
            return
        }

        if shouldRun {
            try? await model.reloadConfiguration()
            await model.startProxy()
        } else {
            model.stopProxy()
        }
    }

    private func restartProxy() async {
        guard !isAnyProxyActionInFlight else {
            return
        }

        isRestartingProxy = true
        defer { isRestartingProxy = false }

        model.stopProxy()

        do {
            try await model.reloadConfiguration()
        } catch {
            toastCenter.show(toastMessage(prefix: "Failed to restart proxy", error: error))
            return
        }

        await model.startProxy()

        if model.isProxyRunning {
            toastCenter.show("Proxy restarted")
        } else {
            toastCenter.show(failureToastMessage(prefix: "Failed to restart proxy"))
        }
    }

    private func reloadConfig() async {
        guard !isAnyProxyActionInFlight else {
            return
        }

        isReloadingConfig = true
        defer { isReloadingConfig = false }

        let shouldRestartProxy = model.isProxyRunning
        if shouldRestartProxy {
            model.stopProxy()
        }

        do {
            try await model.reloadConfiguration()
        } catch {
            toastCenter.show(toastMessage(prefix: "Failed to reload config", error: error))
            return
        }

        if shouldRestartProxy {
            await model.startProxy()
            guard model.isProxyRunning else {
                toastCenter.show(failureToastMessage(prefix: "Failed to reload config"))
                return
            }
        }

        toastCenter.show("Config reloaded")
    }

    private func confirmQuit() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Quit LLMSwitch?"
        alert.informativeText = "The local proxy will stop until you open the app again."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            model.quit()
        }
    }

    private func openProvidersWindow() {
        DispatchQueue.main.async {
            dismiss()
            openWindow(id: "providers")
            activateWindowTitled("Providers")

            DispatchQueue.main.async {
                activateWindowTitled("Providers")
            }
        }
    }

    private func modelSelectionMenu(for row: ModelSwitchRow) -> some View {
        Menu(row.selectedProviderDisplayName ?? "Select") {
            if row.candidates.isEmpty {
                Text("No provider candidates")
            } else {
                ForEach(row.candidates) { candidate in
                    Button(candidate.providerDisplayName) {
                        Task {
                            await model.setActiveProvider(candidate.providerName, for: row.publicName)
                        }
                    }
                }
            }
        }
        .menuStyle(BorderlessButtonMenuStyle())
        .fixedSize()
        .llmSwitchPointingHandCursor()
    }

    private func failureToastMessage(prefix: String) -> String {
        let detail = model.lastError.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !detail.isEmpty else {
            return prefix
        }
        return "\(prefix): \(detail)"
    }

    private func toastMessage(prefix: String, error: Error) -> String {
        let detail = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !detail.isEmpty else {
            return prefix
        }
        return "\(prefix): \(detail)"
    }

    private func activateWindowTitled(_ title: String) {
        NSApp.activate(ignoringOtherApps: true)

        guard let window = NSApp.windows.first(where: { $0.title == title }) else {
            return
        }

        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
