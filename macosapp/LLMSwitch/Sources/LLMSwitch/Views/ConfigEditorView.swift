import AppKit
import LLMGateway
import SwiftUI

struct ConfigEditorView: View {
    @ObservedObject var state: AppState
    @EnvironmentObject private var toast: ToastCenter
    @State private var selectedProvider: String? = nil
    @State private var isBusy = false

    private var providers: [ProviderConfig] { state.configStore.effectiveConfig.providers }

    var body: some View {
        HSplitView {
            providerList.frame(width: 200)
            if let name = selectedProvider, let p = providers.first(where: { $0.name == name }) {
                providerForm(p)
            } else {
                Text("选择一个 Provider").foregroundStyle(.secondary).frame(
                    maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 720, minHeight: 500)
    }

    // MARK: - Provider List

    private var providerList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Providers").font(.headline).padding(12)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(providers, id: \.name) { p in
                        Button {
                            selectedProvider = p.name
                        } label: {
                            HStack {
                                StatusDot(enabled: !p.disabled)
                                Text(p.name).font(.body)
                                Spacer()
                                Button {
                                    confirmDelete(p.name)
                                } label: {
                                    Image(systemName: "trash").font(.caption)
                                }.buttonStyle(.borderless)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6).contentShape(
                                Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(
                            selectedProvider == p.name
                                ? Color.accentColor.opacity(0.15) : Color.clear)
                    }
                }
            }
            Divider()
            Button {
                addProvider()
            } label: {
                HStack {
                    Image(systemName: "plus")
                    Text("添加 Provider")
                }.padding(12)
            }.buttonStyle(.plain)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Provider Form

    private func providerForm(_ p: ProviderConfig) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(p.name).font(.title3.weight(.semibold))
                    Spacer()
                    Toggle(
                        "启用",
                        isOn: Binding(
                            get: { !p.disabled },
                            set: { _ in
                                Task { try? await state.toggleProviderEnabled(p.name) }
                            })
                    ).toggleStyle(.switch)
                }
                Divider()
                formField("Name", value: p.name).disabled(true)
                formField("Type", value: p.type.rawValue)
                formField("Base URL", value: p.baseURL)
                HStack {
                    Text("API Key").font(.caption).foregroundStyle(.secondary).frame(
                        width: 80, alignment: .trailing)
                    TextField("API Key", text: .constant(p.apiKey)).textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                }
                Divider()
                HStack {
                    Text("Models").font(.headline)
                    Spacer()
                    Button("从上游刷新") { Task { await refreshModels(for: p.name) } }.buttonStyle(
                        .bordered
                    ).disabled(isBusy)
                }
                modelList(p)
            }.padding(20)
        }
    }

    private func modelList(_ p: ProviderConfig) -> some View {
        let ids = loadCachedModels(for: p.name)
        return VStack(alignment: .leading, spacing: 4) {
            if ids.isEmpty {
                Text("点击「从上游刷新」拉取模型列表").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(ids, id: \.self) { mid in
                    ModelRow(
                        p: p, modelID: mid,
                        onToggle: { checked in
                            Task { await toggleModel(p.name, modelID: mid, checked: checked) }
                        },
                        onToggleDisabled: { d in
                            Task { await setModelDisabled(p.name, modelID: mid, disabled: d) }
                        })
                }
            }
        }
    }

    // MARK: - Actions

    private func confirmDelete(_ name: String) {
        let a = NSAlert()
        a.messageText = "删除 Provider?"
        a.informativeText = "将移除 \(name) 及其模型路由。"
        a.addButton(withTitle: "删除")
        a.addButton(withTitle: "取消")
        if a.runModal() == .alertFirstButtonReturn {
            let cfg = state.configStore.effectiveConfig
            let newCfg = GatewayConfig(
                listen: cfg.listen, auth: cfg.auth, models: cfg.models,
                providers: cfg.providers.filter { $0.name != name })
            try? state.configStore.saveConfig(newCfg)
            if selectedProvider == name { selectedProvider = nil }
            Task { try? await state.reloadConfig() }
        }
    }

    private func addProvider() {
        let name = "new-\(providers.count + 1)"
        let cfg = state.configStore.effectiveConfig
        let p = ProviderConfig(
            name: name, type: .openai, baseURL: "https://api.example.com", apiKey: "")
        let newCfg = GatewayConfig(
            listen: cfg.listen, auth: cfg.auth, models: cfg.models, providers: cfg.providers + [p])
        try? state.configStore.saveConfig(newCfg)
        selectedProvider = name
    }

    private func refreshModels(for name: String) async {
        isBusy = true
        defer { isBusy = false }
        guard let p = state.configStore.effectiveConfig.provider(named: name) else { return }
        do {
            let models = try await ModelFetcher().fetchModels(from: p)
            saveCachedModels(models.map(\.id), for: name)
            toast.show("已刷新 \(models.count) 个模型")
        } catch { toast.show("刷新失败: \(error.localizedDescription)") }
    }

    private func toggleModel(_ pn: String, modelID: String, checked: Bool) async {
        let cfg = state.configStore.effectiveConfig
        guard let idx = cfg.providers.firstIndex(where: { $0.name == pn }) else { return }
        var p = cfg.providers[idx]
        var m = p.models ?? [:]
        if checked { m[modelID] = ProviderModelConfig() } else { m.removeValue(forKey: modelID) }
        p = ProviderConfig(
            name: p.name, type: p.type, baseURL: p.baseURL, apiKey: p.apiKey, disabled: p.disabled,
            models: m.isEmpty ? nil : m, aliases: p.aliases)
        var ps = cfg.providers
        ps[idx] = p
        try? state.configStore.saveConfig(
            GatewayConfig(listen: cfg.listen, auth: cfg.auth, models: cfg.models, providers: ps))
    }

    private func setModelDisabled(_ pn: String, modelID: String, disabled: Bool) async {
        let cfg = state.configStore.effectiveConfig
        guard let idx = cfg.providers.firstIndex(where: { $0.name == pn }) else { return }
        var p = cfg.providers[idx]
        var m = p.models ?? [:]
        if var mc = m[modelID] {
            mc = ProviderModelConfig(reasoningEfforts: mc.reasoningEfforts, disabled: disabled)
            m[modelID] = mc
        }
        p = ProviderConfig(
            name: p.name, type: p.type, baseURL: p.baseURL, apiKey: p.apiKey, disabled: p.disabled,
            models: m.isEmpty ? nil : m, aliases: p.aliases)
        var ps = cfg.providers
        ps[idx] = p
        try? state.configStore.saveConfig(
            GatewayConfig(listen: cfg.listen, auth: cfg.auth, models: cfg.models, providers: ps))
    }

    // MARK: - Cache

    private func cacheURL(for name: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            ".config/llmswitch/cache/\(name)/models.json")
    }
    private func loadCachedModels(for name: String) -> [String] {
        guard let d = try? Data(contentsOf: cacheURL(for: name)),
            let ids = try? JSONDecoder().decode([String].self, from: d)
        else { return [] }
        return ids
    }
    private func saveCachedModels(_ ids: [String], for name: String) {
        let u = cacheURL(for: name)
        try? FileManager.default.createDirectory(
            at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(ids).write(to: u)
    }
}

// MARK: - Model Row (extracted to avoid Binding issues)

private struct ModelRow: View {
    let p: ProviderConfig
    let modelID: String
    let onToggle: (Bool) -> Void
    let onToggleDisabled: (Bool) -> Void

    private var isSelected: Bool { p.models?[modelID] != nil }
    private var isDisabled: Bool { p.models?[modelID]?.disabled ?? false }

    var body: some View {
        HStack {
            Button {
                onToggle(!isSelected)
            } label: {
                Image(systemName: isSelected ? "checkmark.square" : "square")
            }.buttonStyle(.borderless)
            Text(modelID).font(.body)
            if isSelected {
                Spacer()
                Button {
                    onToggleDisabled(!isDisabled)
                } label: {
                    Text(isDisabled ? "已禁用" : "已启用").font(.caption).foregroundStyle(
                        isDisabled ? .red : .green)
                }.buttonStyle(.borderless)
            }
        }.padding(.vertical, 2)
    }
}

private func formField(_ label: String, value: String) -> some View {
    HStack {
        Text(label).font(.caption).foregroundStyle(.secondary).frame(
            width: 80, alignment: .trailing)
        TextField(label, text: .constant(value)).textFieldStyle(.roundedBorder)
    }
}
