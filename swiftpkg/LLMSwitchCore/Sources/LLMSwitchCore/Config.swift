import Foundation

public struct ListenAddress: Equatable, Sendable {
    public let host: String
    public let port: Int

    public init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    public init(parsing value: String) throws {
        guard let separator = value.lastIndex(of: ":") else {
            throw ConfigError.invalidListenAddress(value)
        }

        let host = String(value[..<separator])
        let portString = String(value[value.index(after: separator)...])

        guard !host.isEmpty, let port = Int(portString), (1...65535).contains(port) else {
            throw ConfigError.invalidListenAddress(value)
        }

        self.host = host
        self.port = port
    }

    public var stringValue: String {
        "\(host):\(port)"
    }
}

public struct ProviderConfig: Equatable, Sendable {
    public let name: String
    public let displayName: String?
    public let baseURL: URL
    public let apiKey: String
    public let enabled: Bool

    public init(name: String, displayName: String?, baseURL: URL, apiKey: String, enabled: Bool) {
        self.name = name
        self.displayName = displayName
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.enabled = enabled
    }

    public var resolvedDisplayName: String {
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? name : trimmed
    }
}

public struct AppSettings: Equatable, Sendable {
    public let listenAddress: ListenAddress
    public let modelRefreshIntervalSeconds: Int
    public let requestTimeoutSeconds: Int
    public let apiKey: String

    public init(
        listenAddress: ListenAddress,
        modelRefreshIntervalSeconds: Int,
        requestTimeoutSeconds: Int,
        apiKey: String
    ) {
        self.listenAddress = listenAddress
        self.modelRefreshIntervalSeconds = modelRefreshIntervalSeconds
        self.requestTimeoutSeconds = requestTimeoutSeconds
        self.apiKey = apiKey
    }

    public var listen: String {
        listenAddress.stringValue
    }
}

public struct AppConfig: Equatable, Sendable {
    public let app: AppSettings
    public let providers: [String: ProviderConfig]

    public init(app: AppSettings, providers: [String: ProviderConfig]) {
        self.app = app
        self.providers = providers
    }
}

public enum ConfigError: LocalizedError, Sendable {
    case missingFile(URL)
    case missingTable(String)
    case missingKey(String)
    case invalidType(String)
    case invalidListenAddress(String)
    case invalidURL(String)
    case unsupportedScheme(String)
    case emptyAPIKey
    case legacyEnvironmentAPIKeyRemoved(String)

    public var errorDescription: String? {
        switch self {
        case let .missingFile(url):
            return "Config file does not exist: \(url.path)"
        case let .missingTable(name):
            return "Missing TOML table: \(name)"
        case let .missingKey(name):
            return "Missing required config key: \(name)"
        case let .invalidType(name):
            return "Invalid config value type for key: \(name)"
        case let .invalidListenAddress(value):
            return "Invalid listen address: \(value)"
        case let .invalidURL(value):
            return "Invalid provider baseUrl: \(value)"
        case let .unsupportedScheme(value):
            return "Provider baseUrl must use http or https: \(value)"
        case .emptyAPIKey:
            return "API key cannot be empty"
        case let .legacyEnvironmentAPIKeyRemoved(path):
            return "`env:` apiKey syntax has been removed, update \(path) to a literal apiKey"
        }
    }
}

public struct ConfigStore: Sendable {
    public let paths: AppPaths

    public init(paths: AppPaths) {
        self.paths = paths
    }

    public func load() throws -> AppConfig {
        guard FileManager.default.fileExists(atPath: paths.configFile.path) else {
            throw ConfigError.missingFile(paths.configFile)
        }

        let source = try String(contentsOf: paths.configFile, encoding: .utf8)
        let document = try TOMLParser.parse(source)
        return try Self.decode(document: document)
    }

    public func save(_ config: AppConfig) throws {
        try paths.ensureDirectories()
        try Self.serialize(config).write(to: paths.configFile, atomically: true, encoding: .utf8)
    }

    static func decode(document: TOMLDocument) throws -> AppConfig {
        guard let appTable = document.table(at: ["app"]) else {
            throw ConfigError.missingTable("app")
        }

        let listen = try requiredString("listen", from: appTable, path: "app.listen")
        let refreshInterval = try requiredInt(
            "modelRefreshIntervalSeconds",
            from: appTable,
            path: "app.modelRefreshIntervalSeconds"
        )
        let timeout = try requiredInt(
            "requestTimeoutSeconds",
            from: appTable,
            path: "app.requestTimeoutSeconds"
        )
        let apiKey = try requiredString("apiKey", from: appTable, path: "app.apiKey")
        try validateLiteralAPIKey(apiKey, path: "app.apiKey")

        guard let providersTable = document.table(at: ["providers"]) else {
            throw ConfigError.missingTable("providers")
        }

        var providers: [String: ProviderConfig] = [:]
        for name in providersTable.keys.sorted() {
            guard let providerTable = providersTable[name]?.tableValue else {
                throw ConfigError.invalidType("providers.\(name)")
            }

            let baseURLString = try requiredString("baseUrl", from: providerTable, path: "providers.\(name).baseUrl")
            let apiKey = try requiredString("apiKey", from: providerTable, path: "providers.\(name).apiKey")
            let enabled = try requiredBool("enabled", from: providerTable, path: "providers.\(name).enabled")
            let displayName = try optionalString("displayName", from: providerTable, path: "providers.\(name).displayName")
            try validateLiteralAPIKey(apiKey, path: "providers.\(name).apiKey")

            guard let baseURL = URL(string: baseURLString) else {
                throw ConfigError.invalidURL(baseURLString)
            }
            guard let scheme = baseURL.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                throw ConfigError.unsupportedScheme(baseURLString)
            }

            providers[name] = ProviderConfig(
                name: name,
                displayName: displayName,
                baseURL: baseURL,
                apiKey: apiKey,
                enabled: enabled
            )
        }

        return AppConfig(
            app: AppSettings(
                listenAddress: try ListenAddress(parsing: listen),
                modelRefreshIntervalSeconds: refreshInterval,
                requestTimeoutSeconds: timeout,
                apiKey: apiKey
            ),
            providers: providers
        )
    }

    public static func serialize(_ config: AppConfig) -> String {
        var lines: [String] = []

        lines.append("[app]")
        lines.append("listen = \(quote(config.app.listen))")
        lines.append("modelRefreshIntervalSeconds = \(config.app.modelRefreshIntervalSeconds)")
        lines.append("requestTimeoutSeconds = \(config.app.requestTimeoutSeconds)")
        lines.append("apiKey = \(quote(config.app.apiKey))")
        lines.append("")
        lines.append("[providers]")

        for providerName in config.providers.keys.sorted() {
            guard let provider = config.providers[providerName] else {
                continue
            }

            lines.append("")
            lines.append("[providers.\(quoteKey(provider.name))]")
            if let displayName = provider.displayName?.trimmingCharacters(in: .whitespacesAndNewlines),
               !displayName.isEmpty,
               displayName != provider.name {
                lines.append("displayName = \(quote(displayName))")
            }
            lines.append("baseUrl = \(quote(provider.baseURL.absoluteString))")
            lines.append("apiKey = \(quote(provider.apiKey))")
            lines.append("enabled = \(provider.enabled ? "true" : "false")")
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func requiredString(
        _ key: String,
        from table: [String: TOMLValue],
        path: String
    ) throws -> String {
        guard let value = table[key] else {
            throw ConfigError.missingKey(path)
        }
        guard let stringValue = value.stringValue else {
            throw ConfigError.invalidType(path)
        }
        return stringValue
    }

    private static func optionalString(
        _ key: String,
        from table: [String: TOMLValue],
        path: String
    ) throws -> String? {
        guard let value = table[key] else {
            return nil
        }
        guard let stringValue = value.stringValue else {
            throw ConfigError.invalidType(path)
        }
        return stringValue
    }

    private static func requiredInt(
        _ key: String,
        from table: [String: TOMLValue],
        path: String
    ) throws -> Int {
        guard let value = table[key] else {
            throw ConfigError.missingKey(path)
        }
        guard let intValue = value.intValue else {
            throw ConfigError.invalidType(path)
        }
        return intValue
    }

    private static func requiredBool(
        _ key: String,
        from table: [String: TOMLValue],
        path: String
    ) throws -> Bool {
        guard let value = table[key] else {
            throw ConfigError.missingKey(path)
        }
        guard let boolValue = value.boolValue else {
            throw ConfigError.invalidType(path)
        }
        return boolValue
    }

    private static func validateLiteralAPIKey(_ apiKey: String, path: String) throws {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ConfigError.emptyAPIKey
        }
        if apiKey.hasPrefix("env:") {
            throw ConfigError.legacyEnvironmentAPIKeyRemoved(path)
        }
    }

    private static func quote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func quoteKey(_ value: String) -> String {
        quote(value)
    }
}
