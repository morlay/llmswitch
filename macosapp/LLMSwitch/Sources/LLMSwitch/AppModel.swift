import AppKit
import Combine
import Foundation
import LLMSwitchCore

struct ProviderModelRow: Identifiable, Sendable {
    let providerName: String
    let modelName: String
    let featureSummary: String
    let isEnabled: Bool

    var id: String { "\(providerName):\(modelName)" }
}

struct ProviderStatusRow: Identifiable, Sendable {
    let providerName: String
    let displayName: String
    let baseURL: String
    let isEnabled: Bool
    let healthState: ProviderHealthState
    let modelCount: Int
    let lastFetchedAt: String
    let errorMessage: String?
    let models: [ProviderModelRow]

    var id: String { providerName }
}

enum ProviderHealthState: Sendable {
    case healthy
    case inactive
}

struct ModelSwitchCandidateRow: Identifiable, Hashable, Sendable {
    let providerName: String
    let providerDisplayName: String
    let upstreamModel: String

    var id: String { "\(providerName):\(upstreamModel)" }
}

struct ModelSwitchRow: Identifiable, Sendable {
    let publicName: String
    let candidates: [ModelSwitchCandidateRow]
    let selectedProviderName: String?
    let selectedProviderDisplayName: String?

    var id: String { publicName }

    var pickerSelection: String {
        selectedProviderName ?? "__unselected__"
    }
}

struct ProviderDraft: Sendable {
    var name: String
    var displayName: String
    var baseURL: String
    var apiKey: String
    var enabled: Bool
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var statusLine = "Starting..."
    @Published private(set) var detailLine = ""
    @Published private(set) var isProxyRunning = false
    @Published private(set) var lastRefreshLine = "Not refreshed yet"
    @Published private(set) var lastError = ""
    @Published private(set) var providerCount = 0
    @Published private(set) var enabledModelCount = 0
    @Published private(set) var configRootPath = ""
    @Published private(set) var configFilePath = ""
    @Published private(set) var stateFilePath = ""
    @Published private(set) var providerStatuses: [ProviderStatusRow] = []
    @Published private(set) var modelSwitchRows: [ModelSwitchRow] = []
    @Published private(set) var serviceAPIKey = ""
    @Published private(set) var serviceAPIKeyPreview = ""
    @Published private(set) var listenAddress = ""

    private let environment: [String: String]
    private let paths: AppPaths
    private var config: AppConfig?
    private var state: AppState = .empty
    private var cacheStore: CacheStore
    private var snapshots: [String: ProviderCacheSnapshot] = [:]
    private var proxy: ProxyService?
    private var server: HTTPServer?
    private var didBootstrap = false

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
        self.paths = AppPaths(configRoot: AppPaths.defaultRoot(environment: environment))
        self.cacheStore = CacheStore(paths: AppPaths(configRoot: AppPaths.defaultRoot(environment: environment)))
        self.configRootPath = self.paths.configRoot.path
        self.configFilePath = self.paths.configFile.path
        self.stateFilePath = self.paths.stateFile.path
        self.detailLine = self.paths.configRoot.path
    }

    func bootstrap() async {
        guard !didBootstrap else {
            return
        }
        didBootstrap = true

        do {
            try paths.ensureDirectories()
            try ensureBootstrapConfigExists()
            try migrateMissingAppAPIKeyIfNeeded()
            try await reloadConfiguration()
            await startProxy()
        } catch {
            applyError("Bootstrap failed", error: error)
        }
    }

    func reloadConfiguration() async throws {
        lastError = ""
        try migrateMissingAppAPIKeyIfNeeded()

        guard FileManager.default.fileExists(atPath: paths.configFile.path) else {
            config = nil
            state = .empty
            snapshots = [:]
            proxy = nil
            server?.stop()
            server = nil
            isProxyRunning = false
            providerCount = 0
            enabledModelCount = 0
            serviceAPIKey = ""
            serviceAPIKeyPreview = ""
            listenAddress = ""
            providerStatuses = []
            modelSwitchRows = []
            statusLine = "Config missing"
            detailLine = paths.configRoot.path
            return
        }

        let configStore = ConfigStore(paths: paths)
        let config = try configStore.load()
        let loadedState = try StateStore(paths: paths).load()
        let snapshots = try cacheStore.loadAll(providerNames: Array(config.providers.keys))
        let (normalizedState, didChangeState) = normalizedState(from: loadedState, config: config, snapshots: snapshots)
        if didChangeState {
            try StateStore(paths: paths).save(normalizedState)
        }

        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.timeoutIntervalForRequest = TimeInterval(config.app.requestTimeoutSeconds)
        sessionConfiguration.timeoutIntervalForResource = TimeInterval(config.app.requestTimeoutSeconds)
        let session = URLSession(configuration: sessionConfiguration)

        let providerClient = ProviderClient(session: session)
        let proxy = ProxyService(
            config: config,
            state: normalizedState,
            cacheStore: cacheStore,
            providerClient: providerClient,
            session: session,
            snapshots: snapshots
        )

        self.config = config
        self.state = normalizedState
        self.snapshots = snapshots
        self.proxy = proxy
        self.providerCount = config.providers.count
        self.enabledModelCount = uniqueEnabledModelNames(state: normalizedState, config: config).count
        self.serviceAPIKey = config.app.apiKey
        self.serviceAPIKeyPreview = Self.maskedAPIKey(config.app.apiKey)
        self.listenAddress = config.app.listen
        rebuildStatusRows(config: config, state: normalizedState, snapshots: snapshots)
        self.statusLine = isProxyRunning ? "Proxy running" : "Config loaded"
        self.detailLine = "Proxy target: \(config.app.listen)"
    }

    func startProxy() async {
        guard let config, let proxy else {
            statusLine = "Config missing"
            detailLine = paths.configRoot.path
            return
        }

        guard !isProxyRunning else {
            return
        }

        do {
            let server = HTTPServer(listenAddress: config.app.listenAddress) { request, writer in
                await proxy.handle(request, writer: writer)
            }
            try server.start()
            self.server = server
            self.isProxyRunning = true
            self.statusLine = "Proxy running"
            self.detailLine = config.app.listen
            self.lastError = ""

            Task {
                await self.refreshModels()
            }
        } catch {
            applyError("Failed to start proxy", error: error)
        }
    }

    func stopProxy() {
        server?.stop()
        server = nil
        isProxyRunning = false
        statusLine = "Proxy stopped"
        if let config {
            detailLine = config.app.listen
        }
    }

    func refreshModels() async {
        guard let proxy, let config else {
            statusLine = "Config missing"
            detailLine = paths.configRoot.path
            return
        }

        await proxy.refreshModelCatalogs()
        do {
            try syncSnapshotsFromCache(using: config)
            let (normalizedState, didChangeState) = normalizedState(from: state, config: config, snapshots: snapshots)
            if didChangeState {
                try StateStore(paths: paths).save(normalizedState)
                self.state = normalizedState
                rebuildStatusRows(config: config, state: normalizedState, snapshots: snapshots)
            }
        } catch {
            applyError("Failed to reload model cache", error: error)
            return
        }

        lastRefreshLine = "Refreshed at \(Self.timestampString(from: Date()))"
        statusLine = isProxyRunning ? "Proxy running" : "Config loaded"
        lastError = ""
    }

    func resetServiceAPIKey() async throws {
        guard var config else {
            return
        }

        config = AppConfig(
            app: AppSettings(
                listenAddress: config.app.listenAddress,
                modelRefreshIntervalSeconds: config.app.modelRefreshIntervalSeconds,
                requestTimeoutSeconds: config.app.requestTimeoutSeconds,
                apiKey: Self.generateServiceAPIKey()
            ),
            providers: config.providers
        )

        try await persist(config: config, state: state, errorPrefix: "Failed to reset service apiKey")
    }

    func draftForProvider(named providerName: String) -> ProviderDraft? {
        guard let provider = config?.providers[providerName] else {
            return nil
        }

        return ProviderDraft(
            name: provider.name,
            displayName: provider.displayName ?? "",
            baseURL: provider.baseURL.absoluteString,
            apiKey: provider.apiKey,
            enabled: provider.enabled
        )
    }

    func copyServiceAPIKey() {
        guard !serviceAPIKey.isEmpty else {
            return
        }

        copyToPasteboard(serviceAPIKey)
    }

    func copyBaseURL() {
        guard !listenAddress.isEmpty else {
            return
        }

        copyToPasteboard(listenAddress)
    }

    func addProvider(_ draft: ProviderDraft) async throws {
        guard var config else {
            return
        }

        let provider = try makeProviderConfig(from: draft)
        guard config.providers[provider.name] == nil else {
            throw NSError(
                domain: "LLMSwitch",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Provider \(provider.name) already exists"]
            )
        }

        config = AppConfig(app: config.app, providers: config.providers.merging([provider.name: provider]) { _, new in new })
        try await persist(config: config, state: state, errorPrefix: "Failed to add provider")
    }

    func updateProvider(originalName: String, draft: ProviderDraft) async throws {
        guard var config else {
            return
        }

        let provider = try makeProviderConfig(from: draft)
        var providers = config.providers
        providers.removeValue(forKey: originalName)
        providers[provider.name] = provider

        var nextState = state
        if originalName != provider.name {
            if let providerModels = nextState.enabledProviderModels.removeValue(forKey: originalName) {
                nextState.enabledProviderModels[provider.name] = providerModels
            }
            nextState.activeBindings = Dictionary(uniqueKeysWithValues: nextState.activeBindings.map { modelName, binding in
                if binding.provider == originalName {
                    return (modelName, ActiveBinding(provider: provider.name, upstreamModel: binding.upstreamModel))
                }
                return (modelName, binding)
            })
        }

        config = AppConfig(app: config.app, providers: providers)
        try await persist(config: config, state: nextState, errorPrefix: "Failed to update provider")
    }

    func setProviderEnabled(_ providerName: String, enabled: Bool) async throws {
        guard var config, let provider = config.providers[providerName] else {
            return
        }

        let updatedProvider = ProviderConfig(
            name: provider.name,
            displayName: provider.displayName,
            baseURL: provider.baseURL,
            apiKey: provider.apiKey,
            enabled: enabled
        )

        var providers = config.providers
        providers[providerName] = updatedProvider
        config = AppConfig(app: config.app, providers: providers)

        let nextState = rebalancedState(afterConfigChange: config, state: state, snapshots: snapshots)
        try await persist(config: config, state: nextState, errorPrefix: "Failed to update provider")
    }

    func deleteProvider(_ providerName: String) async throws {
        guard var config else {
            return
        }

        var providers = config.providers
        providers.removeValue(forKey: providerName)
        config = AppConfig(app: config.app, providers: providers)

        var nextState = state
        nextState.enabledProviderModels.removeValue(forKey: providerName)
        nextState.activeBindings = nextState.activeBindings.filter { _, binding in
            binding.provider != providerName
        }
        nextState = rebalancedState(afterConfigChange: config, state: nextState, snapshots: snapshots)
        try await persist(config: config, state: nextState, errorPrefix: "Failed to delete provider")
    }

    func setProviderModelEnabled(providerName: String, modelName: String, enabled: Bool) async {
        var nextState = state
        if enabled {
            nextState.enabledProviderModels[providerName, default: [:]][modelName] = true
        } else {
            nextState.enabledProviderModels[providerName]?[modelName] = nil
            if nextState.enabledProviderModels[providerName]?.isEmpty == true {
                nextState.enabledProviderModels[providerName] = nil
            }
        }

        nextState = rebalancedState(afterConfigChange: config, state: nextState, snapshots: snapshots)
        await persistState(nextState, errorPrefix: "Failed to save model switch")
    }

    func setActiveProvider(_ providerName: String, for modelName: String) async {
        guard candidateRows(for: modelName, state: state, config: config, snapshots: snapshots)
            .contains(where: { $0.providerName == providerName }) || snapshots[providerName]?.models.contains(where: { $0.id == modelName }) == true else {
            return
        }

        var nextState = state
        nextState.enabledProviderModels[providerName, default: [:]][modelName] = true
        nextState.activeBindings[modelName] = ActiveBinding(provider: providerName, upstreamModel: modelName)
        nextState = rebalancedState(afterConfigChange: config, state: nextState, snapshots: snapshots)
        await persistState(nextState, errorPrefix: "Failed to save provider binding")
    }

    func openConfigDirectory() {
        do {
            try paths.ensureDirectories()
            NSWorkspace.shared.activateFileViewerSelecting([paths.configRoot])
        } catch {
            applyError("Failed to open config directory", error: error)
        }
    }

    func openConfigFile() {
        openURL(paths.configFile)
    }

    func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func ensureBootstrapConfigExists() throws {
        guard !FileManager.default.fileExists(atPath: paths.configFile.path) else {
            return
        }

        let config = SampleConfig.defaultConfig(serviceAPIKey: Self.generateServiceAPIKey())
        try ConfigStore(paths: paths).save(config)
    }

    private func migrateMissingAppAPIKeyIfNeeded() throws {
        guard FileManager.default.fileExists(atPath: paths.configFile.path) else {
            return
        }

        let source = try String(contentsOf: paths.configFile, encoding: .utf8)
        let document = try TOMLParser.parse(source)
        guard let appTable = document.table(at: ["app"]), appTable["apiKey"] == nil else {
            return
        }

        let generatedKey = Self.generateServiceAPIKey()
        var outputLines: [String] = []
        var inserted = false
        var inAppSection = false

        for line in source.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                if inAppSection && !inserted {
                    outputLines.append("apiKey = \"\(generatedKey)\"")
                    inserted = true
                }
                inAppSection = trimmed == "[app]"
            }
            outputLines.append(line)
        }

        if inAppSection && !inserted {
            outputLines.append("apiKey = \"\(generatedKey)\"")
        }

        try outputLines.joined(separator: "\n").write(to: paths.configFile, atomically: true, encoding: .utf8)
    }

    private func persist(config: AppConfig, state: AppState, errorPrefix: String) async throws {
        let shouldRestartProxy = isProxyRunning
        if shouldRestartProxy {
            stopProxy()
        }

        try ConfigStore(paths: paths).save(config)
        try StateStore(paths: paths).save(state)
        self.config = config
        self.state = state
        try await reloadConfiguration()

        if shouldRestartProxy {
            await startProxy()
        }
    }

    private func persistState(_ nextState: AppState, errorPrefix: String) async {
        let shouldRestartProxy = isProxyRunning
        if shouldRestartProxy {
            stopProxy()
        }

        do {
            try StateStore(paths: paths).save(nextState)
            self.state = nextState
            try await reloadConfiguration()
            if shouldRestartProxy {
                await startProxy()
            }
        } catch {
            applyError(errorPrefix, error: error)
        }
    }

    private func syncSnapshotsFromCache(using config: AppConfig) throws {
        let snapshots = try cacheStore.loadAll(providerNames: Array(config.providers.keys))
        self.snapshots = snapshots
        rebuildStatusRows(config: config, state: state, snapshots: snapshots)
    }

    private func rebuildStatusRows(
        config: AppConfig,
        state: AppState,
        snapshots: [String: ProviderCacheSnapshot]
    ) {
        providerStatuses = config.providers.keys.sorted().compactMap { providerName in
            guard let provider = config.providers[providerName] else {
                return nil
            }

            let snapshot = snapshots[providerName]
            let healthState: ProviderHealthState
            if provider.enabled, snapshot?.meta.wasSuccessful == true {
                healthState = .healthy
            } else {
                healthState = .inactive
            }

            let models = (snapshot?.models ?? []).sorted { $0.id < $1.id }.map { model in
                ProviderModelRow(
                    providerName: providerName,
                    modelName: model.id,
                    featureSummary: Self.featureSummary(for: model),
                    isEnabled: state.enabledProviderModels[providerName]?[model.id] == true
                )
            }

            return ProviderStatusRow(
                providerName: providerName,
                displayName: provider.resolvedDisplayName,
                baseURL: provider.baseURL.absoluteString,
                isEnabled: provider.enabled,
                healthState: healthState,
                modelCount: snapshot?.models.count ?? 0,
                lastFetchedAt: snapshot.map { Self.timestampString(from: $0.meta.fetchedAt) } ?? "Never",
                errorMessage: snapshot?.meta.errorMessage,
                models: models
            )
        }

        modelSwitchRows = uniqueEnabledModelNames(state: state, config: config).map { modelName in
            let candidates = candidateRows(for: modelName, state: state, config: config, snapshots: snapshots)
            let selected = selectedBinding(for: modelName, candidates: candidates, state: state)
            return ModelSwitchRow(
                publicName: modelName,
                candidates: candidates,
                selectedProviderName: selected?.providerName,
                selectedProviderDisplayName: selected?.providerDisplayName
            )
        }.sorted { $0.publicName < $1.publicName }
    }

    private func normalizedState(
        from state: AppState,
        config: AppConfig,
        snapshots: [String: ProviderCacheSnapshot]
    ) -> (AppState, Bool) {
        var nextState = state
        var didChange = false

        if !state.legacyEnabledModels.isEmpty {
            for (modelName, enabled) in state.legacyEnabledModels where enabled {
                for providerName in config.providers.keys.sorted() {
                    guard snapshots[providerName]?.models.contains(where: { $0.id == modelName }) == true else {
                        continue
                    }
                    if nextState.enabledProviderModels[providerName]?[modelName] != true {
                        nextState.enabledProviderModels[providerName, default: [:]][modelName] = true
                        didChange = true
                    }
                }
            }
            nextState.legacyEnabledModels = [:]
            didChange = true
        }

        let validProviders = Set(config.providers.keys)
        let filteredProviderModels = nextState.enabledProviderModels.filter { providerName, _ in
            validProviders.contains(providerName)
        }
        if filteredProviderModels.count != nextState.enabledProviderModels.count {
            nextState.enabledProviderModels = filteredProviderModels
            didChange = true
        }

        for providerName in nextState.enabledProviderModels.keys.sorted() {
            let existing = nextState.enabledProviderModels[providerName] ?? [:]
            let filtered = existing.filter { modelName, enabled in
                enabled && snapshots[providerName]?.models.contains(where: { $0.id == modelName }) == true
            }
            if filtered != existing {
                nextState.enabledProviderModels[providerName] = filtered.isEmpty ? nil : filtered
                didChange = true
            }
        }

        let rebalanced = rebalancedState(afterConfigChange: config, state: nextState, snapshots: snapshots)
        if rebalanced != nextState {
            nextState = rebalanced
            didChange = true
        }

        return (nextState, didChange)
    }

    private func rebalancedState(
        afterConfigChange config: AppConfig?,
        state: AppState,
        snapshots: [String: ProviderCacheSnapshot]
    ) -> AppState {
        guard let config else {
            return state
        }

        var nextState = state
        let modelNames = uniqueEnabledModelNames(state: state, config: config)
        for modelName in modelNames {
            let candidates = candidateRows(for: modelName, state: nextState, config: config, snapshots: snapshots)
            if let binding = nextState.activeBindings[modelName],
               candidates.contains(where: { $0.providerName == binding.provider && $0.upstreamModel == binding.upstreamModel }) {
                continue
            }

            if candidates.count == 1, let candidate = candidates.first {
                nextState.activeBindings[modelName] = ActiveBinding(
                    provider: candidate.providerName,
                    upstreamModel: candidate.upstreamModel
                )
            } else {
                nextState.activeBindings[modelName] = nil
            }
        }

        let validModelNames = Set(modelNames)
        nextState.activeBindings = nextState.activeBindings.filter { modelName, _ in
            validModelNames.contains(modelName)
        }
        return nextState
    }

    private func uniqueEnabledModelNames(state: AppState, config: AppConfig?) -> [String] {
        let allowedProviders = Set(config?.providers.compactMap { key, value in
            value.enabled ? key : nil
        } ?? [])

        return Set(state.enabledProviderModels.compactMap { providerName, providerModels in
            allowedProviders.contains(providerName) ? providerModels.filter(\.value).map(\.key) : []
        }.flatMap { $0 }).sorted()
    }

    private func candidateRows(
        for modelName: String,
        state: AppState,
        config: AppConfig?,
        snapshots: [String: ProviderCacheSnapshot]
    ) -> [ModelSwitchCandidateRow] {
        guard let config else {
            return []
        }

        return config.providers.keys.sorted().compactMap { providerName in
            guard let provider = config.providers[providerName], provider.enabled else {
                return nil
            }
            guard state.enabledProviderModels[providerName]?[modelName] == true else {
                return nil
            }
            guard snapshots[providerName]?.models.contains(where: { $0.id == modelName }) == true else {
                return nil
            }
            return ModelSwitchCandidateRow(
                providerName: providerName,
                providerDisplayName: provider.resolvedDisplayName,
                upstreamModel: modelName
            )
        }
    }

    private func selectedBinding(
        for modelName: String,
        candidates: [ModelSwitchCandidateRow],
        state: AppState
    ) -> ModelSwitchCandidateRow? {
        if let binding = state.activeBindings[modelName] {
            return candidates.first(where: { $0.providerName == binding.provider && $0.upstreamModel == binding.upstreamModel })
        }
        return candidates.count == 1 ? candidates.first : nil
    }

    private func makeProviderConfig(from draft: ProviderDraft) throws -> ProviderConfig {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURLString = draft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let apiKey = draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else {
            throw NSError(domain: "LLMSwitch", code: 2, userInfo: [NSLocalizedDescriptionKey: "Provider name is required"])
        }
        guard name.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else {
            throw NSError(
                domain: "LLMSwitch",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "Provider name only supports letters, numbers, _ and -"]
            )
        }
        guard !apiKey.isEmpty else {
            throw NSError(domain: "LLMSwitch", code: 3, userInfo: [NSLocalizedDescriptionKey: "Provider apiKey is required"])
        }
        if apiKey.hasPrefix("env:") {
            throw NSError(domain: "LLMSwitch", code: 4, userInfo: [NSLocalizedDescriptionKey: "`env:` apiKey syntax has been removed"])
        }
        guard let baseURL = URL(string: baseURLString),
              let scheme = baseURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw NSError(domain: "LLMSwitch", code: 5, userInfo: [NSLocalizedDescriptionKey: "Provider baseUrl must use http or https"])
        }

        return ProviderConfig(
            name: name,
            displayName: displayName.isEmpty ? nil : displayName,
            baseURL: baseURL,
            apiKey: apiKey,
            enabled: draft.enabled
        )
    }

    private func openURL(_ url: URL) {
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting([url.deletingLastPathComponent()])
        }
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func applyError(_ prefix: String, error: Error) {
        statusLine = prefix
        detailLine = error.localizedDescription
        lastError = error.localizedDescription
        isProxyRunning = false
    }

    private static func timestampString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    private static func maskedAPIKey(_ apiKey: String) -> String {
        guard apiKey.count > 8 else {
            return apiKey
        }

        let prefix = apiKey.prefix(4)
        let suffix = apiKey.suffix(4)
        return "\(prefix)…\(suffix)"
    }

    private static func generateServiceAPIKey() -> String {
        "llmsw_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }

    private static func featureSummary(for model: ProviderModel) -> String {
        if !model.capabilities.isEmpty {
            return model.capabilities.prefix(4).joined(separator: ", ")
        }
        if let object = model.object, !object.isEmpty {
            return object
        }
        return "OpenAI compatible"
    }
}
