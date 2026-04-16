import Combine
import Foundation
import LLMGateway

@MainActor
final class AppState: ObservableObject {
    let configStore: ConfigStore
    let gatewayRuntime: GatewayRuntime

    @Published var providerRows: [ProviderRow] = []
    @Published var modelRouteRows: [ModelRouteRow] = []
    @Published var statusLine = "Starting..."
    @Published var lastError = ""

    private var cancellables = Set<AnyCancellable>()

    init() {
        let paths = AppPaths.default()
        self.configStore = ConfigStore(paths: paths)
        self.gatewayRuntime = GatewayRuntime()
        configStore.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }.store(in: &cancellables)
    }

    func bootstrap() async {
        do {
            try configStore.ensureConfigExists()
            try configStore.loadConfig()
            try configStore.loadState()
            await gatewayRuntime.apply(
                config: configStore.effectiveConfig, state: configStore.runtimeState)
            await rebuildRows()
            await startProxy()
        } catch {
            lastError = error.localizedDescription
            statusLine = "Bootstrap failed"
        }
    }

    func reloadConfig() async throws {
        try configStore.loadConfig()
        try configStore.loadState()
        await gatewayRuntime.apply(
            config: configStore.effectiveConfig, state: configStore.runtimeState)
        await rebuildRows()
    }

    func startProxy() async {
        do {
            try gatewayRuntime.start()
            statusLine = "Proxy running"
        } catch {
            lastError = error.localizedDescription
            statusLine = "Failed to start"
        }
    }

    func stopProxy() {
        gatewayRuntime.stop()
        statusLine = "Proxy stopped"
    }

    func toggleProviderEnabled(_ name: String) async throws {
        let cfg = configStore.effectiveConfig
        guard let idx = cfg.providers.firstIndex(where: { $0.name == name }) else { return }
        let p = cfg.providers[idx]
        let updated = ProviderConfig(
            name: p.name, type: p.type, baseURL: p.baseURL, apiKey: p.apiKey, disabled: !p.disabled,
            models: p.models, aliases: p.aliases)
        var providers = cfg.providers
        providers[idx] = updated
        let newConfig = GatewayConfig(
            listen: cfg.listen, auth: cfg.auth, models: cfg.models, providers: providers)
        try configStore.saveConfig(newConfig)
        configStore.runtimeState = GatewayRuntimeState.bootstrap(from: newConfig)
        await gatewayRuntime.updateService(config: newConfig, state: configStore.runtimeState)
        await rebuildRows()
    }

    func setModelRouteProvider(modelName: String, providerName: String) async throws {
        let cfg = configStore.effectiveConfig
        guard cfg.provider(named: providerName) != nil else { return }
        var models = cfg.models
        models[modelName] = "\(providerName)/*"
        let newConfig = GatewayConfig(
            listen: cfg.listen, auth: cfg.auth, models: models, providers: cfg.providers)
        try configStore.saveConfig(newConfig)
        configStore.runtimeState = GatewayRuntimeState.bootstrap(from: newConfig)
        await gatewayRuntime.updateService(config: newConfig, state: configStore.runtimeState)
        await rebuildRows()
    }

    func modelProviderCandidates(for modelName: String) -> [String] {
        configStore.effectiveConfig.enabledProviders.compactMap { p in
            if p.aliases?[modelName] != nil || p.models?[modelName] != nil { return p.name }
            return nil
        }
    }

    func queryUsageSummary(since: Date?, until: Date?) async -> TokenUsageSummary? {
        guard let store = gatewayRuntime.usageStore else { return nil }
        return try? await store.queryUsageSummary(since: since, until: until)
    }

    func queryModelUsage(since: Date?, until: Date?) async -> [ModelUsageSummary] {
        guard let store = gatewayRuntime.usageStore else { return [] }
        return (try? await store.queryModelUsage(since: since, until: until)) ?? []
    }

    func queryProviderUsage(since: Date?, until: Date?) async -> [ProviderUsageSummary] {
        guard let store = gatewayRuntime.usageStore else { return [] }
        return (try? await store.queryProviderUsage(since: since, until: until)) ?? []
    }

    func rebuildRows() async {
        let config = configStore.effectiveConfig
        let state = configStore.runtimeState

        providerRows = config.enabledProviders.map { provider in
            ProviderRow(
                name: provider.name, baseURL: provider.baseURL, disabled: provider.disabled,
                modelCount: provider.publicModelIDs.count)
        }

        modelRouteRows = state.activeBindings.keys.sorted().map { modelName in
            let binding = state.binding(for: modelName)
            return ModelRouteRow(
                modelName: modelName, providerName: binding?.provider,
                upstreamModel: binding?.upstreamModel)
        }
    }
}

struct ProviderRow: Identifiable, Sendable {
    let name: String
    let baseURL: String
    let disabled: Bool
    let modelCount: Int
    var id: String { name }
}

struct ModelRouteRow: Identifiable, Sendable {
    let modelName: String
    let providerName: String?
    let upstreamModel: String?
    var id: String { modelName }
    var routeDescription: String {
        if let p = providerName, let u = upstreamModel { return "\(p)/\(u)" }
        return providerName ?? "—"
    }
}

struct AppPaths {
    let configRoot: URL
    static func `default`() -> AppPaths {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
            ".config/llmswitch", isDirectory: true)
        return AppPaths(configRoot: root)
    }
    var configFile: URL { configRoot.appendingPathComponent("config.json") }
}
