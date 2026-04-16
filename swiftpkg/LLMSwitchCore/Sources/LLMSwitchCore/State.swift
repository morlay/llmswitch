import Foundation

public struct ActiveBinding: Equatable, Sendable {
    public let provider: String
    public let upstreamModel: String

    public init(provider: String, upstreamModel: String) {
        self.provider = provider
        self.upstreamModel = upstreamModel
    }
}

public struct AppState: Equatable, Sendable {
    public var enabledProviderModels: [String: [String: Bool]]
    public var activeBindings: [String: ActiveBinding]
    public var legacyEnabledModels: [String: Bool]

    public init(
        enabledProviderModels: [String: [String: Bool]] = [:],
        activeBindings: [String: ActiveBinding] = [:],
        legacyEnabledModels: [String: Bool] = [:]
    ) {
        self.enabledProviderModels = enabledProviderModels
        self.activeBindings = activeBindings
        self.legacyEnabledModels = legacyEnabledModels
    }

    public static let empty = AppState()

    public func serialized() -> String {
        var lines: [String] = []

        lines.append("[enabledProviderModels]")
        for providerName in enabledProviderModels.keys.sorted() {
            let models = enabledProviderModels[providerName] ?? [:]
            lines.append("")
            lines.append("[enabledProviderModels.\(Self.quote(providerName))]")
            for modelName in models.keys.sorted() {
                let value = models[modelName] ?? false
                lines.append("\(Self.quote(modelName)) = \(value ? "true" : "false")")
            }
        }

        for modelName in activeBindings.keys.sorted() {
            guard let binding = activeBindings[modelName] else {
                continue
            }

            lines.append("")
            lines.append("[activeBindings.\(Self.quote(modelName))]")
            lines.append("provider = \(Self.quote(binding.provider))")
            lines.append("upstreamModel = \(Self.quote(binding.upstreamModel))")
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func quote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

public struct StateStore: Sendable {
    public let paths: AppPaths

    public init(paths: AppPaths) {
        self.paths = paths
    }

    public func load() throws -> AppState {
        guard FileManager.default.fileExists(atPath: paths.stateFile.path) else {
            return .empty
        }

        let source = try String(contentsOf: paths.stateFile, encoding: .utf8)
        let document = try TOMLParser.parse(source)

        let providerModelsTable = document.table(at: ["enabledProviderModels"]) ?? [:]
        var enabledProviderModels: [String: [String: Bool]] = [:]
        for providerName in providerModelsTable.keys.sorted() {
            guard let providerTable = providerModelsTable[providerName]?.tableValue else {
                throw ConfigError.invalidType("enabledProviderModels.\(providerName)")
            }
            var modelFlags: [String: Bool] = [:]
            for modelName in providerTable.keys.sorted() {
                guard let flag = providerTable[modelName]?.boolValue else {
                    throw ConfigError.invalidType("enabledProviderModels.\(providerName).\(modelName)")
                }
                modelFlags[modelName] = flag
            }
            enabledProviderModels[providerName] = modelFlags
        }

        let legacyEnabledModelsTable = document.table(at: ["enabledModels"]) ?? [:]
        var legacyEnabledModels: [String: Bool] = [:]
        for modelName in legacyEnabledModelsTable.keys.sorted() {
            guard let flag = legacyEnabledModelsTable[modelName]?.boolValue else {
                throw ConfigError.invalidType("enabledModels.\(modelName)")
            }
            legacyEnabledModels[modelName] = flag
        }

        let bindingsTable = document.table(at: ["activeBindings"]) ?? [:]
        var activeBindings: [String: ActiveBinding] = [:]
        for modelName in bindingsTable.keys.sorted() {
            guard let bindingTable = bindingsTable[modelName]?.tableValue else {
                throw ConfigError.invalidType("activeBindings.\(modelName)")
            }
            guard let provider = bindingTable["provider"]?.stringValue else {
                throw ConfigError.missingKey("activeBindings.\(modelName).provider")
            }
            guard let upstreamModel = bindingTable["upstreamModel"]?.stringValue else {
                throw ConfigError.missingKey("activeBindings.\(modelName).upstreamModel")
            }
            activeBindings[modelName] = ActiveBinding(provider: provider, upstreamModel: upstreamModel)
        }

        return AppState(
            enabledProviderModels: enabledProviderModels,
            activeBindings: activeBindings,
            legacyEnabledModels: legacyEnabledModels
        )
    }

    public func save(_ state: AppState) throws {
        let serialized = state.serialized()
        try serialized.write(to: paths.stateFile, atomically: true, encoding: .utf8)
    }
}
