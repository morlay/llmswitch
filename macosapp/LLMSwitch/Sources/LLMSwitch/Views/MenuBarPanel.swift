import AppKit
import SwiftUI

struct MenuBarPanel: View {
    @ObservedObject var state: AppState
    @EnvironmentObject private var toast: ToastCenter
    @State private var proxyOn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toolbar {
                QuitIconButton { NSApp.terminate(nil) }
                Text("LLM Switch").font(.headline)
                Spacer()
                Toggle("", isOn: $proxyOn)
                    .toggleStyle(.switch).labelsHidden()
                    .onChange(of: proxyOn) { _, on in
                        Task { on ? await state.startProxy() : state.stopProxy() }
                    }
            }
            Divider()

            if state.gatewayRuntime.isRunning {
                Toolbar {
                    Text(state.gatewayRuntime.listenAddress).font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Spacer()
                    CopyAPIKeyIconButton(isDisabled: false, toastMessage: "API key copied") {}
                }
                Divider()
            }

            SectionHeader(title: "Models") {
                if state.modelRouteRows.isEmpty {
                    Text("暂无模型").font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(
                    state.modelRouteRows.filter {
                        !state.modelProviderCandidates(for: $0.modelName).isEmpty
                    }
                ) { row in
                    HStack {
                        Text(row.modelName)
                        Spacer()
                        Menu(row.providerName ?? "未绑定") {
                            let candidates = state.modelProviderCandidates(for: row.modelName)
                            if candidates.isEmpty {
                                Text("无可用 Provider").foregroundStyle(.secondary)
                            } else {
                                ForEach(candidates, id: \.self) { name in
                                    Button(name) {
                                        Task {
                                            do {
                                                try await state.setModelRouteProvider(
                                                    modelName: row.modelName, providerName: name)
                                                toast.show("切换到 \(name)")
                                            } catch {
                                                toast.show("切换失败")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .font(.caption)
                    }
                    .padding(.vertical, 2)
                }
            }

            Divider()

            Toolbar {
                Spacer()
                LLMSwitchIconButton("chart.bar", help: "Usage") {
                    openWindow(titled: "Usage", rootView: UsagePanel(state: state))
                }
                LLMSwitchIconButton("gearshape", help: "Config") {
                    openWindow(
                        titled: "Config",
                        rootView: ConfigEditorView(state: state).environmentObject(toast))
                }
            }
        }
        .frame(width: 280).padding(12)
        .onAppear { proxyOn = state.gatewayRuntime.isRunning }
        .onChange(of: state.gatewayRuntime.isRunning) { _, v in proxyOn = v }
    }

    private func openWindow(titled title: String, rootView: some View) {
        NSApp.activate(ignoringOtherApps: true)
        for w in NSApp.windows where w.title == title {
            w.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = title
        window.contentView = NSHostingView(rootView: AnyView(rootView))
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
