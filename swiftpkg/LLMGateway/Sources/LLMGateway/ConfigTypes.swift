import Foundation

// MARK: - 监听地址

public struct ListenAddress: Equatable, Sendable {
    public let host: String
    public let port: Int
    public init(host: String, port: Int) { self.host = host; self.port = port }
    public var stringValue: String { "\(host):\(port)" }
}

// MARK: - 鉴权配置

public struct AuthConfig: Equatable, Sendable {
    public let apiKey: String
    public init(apiKey: String) { self.apiKey = apiKey }
    public var isProxyManaged: Bool { apiKey == "PROXY_MANAGED" }
}

// MARK: - Provider 类型

public enum ProviderType: String, Sendable, Equatable, Codable {
    case openai
    case openaiCompatible = "openai-compatible"
    public var supportsResponses: Bool {
        switch self { case .openai: return true; case .openaiCompatible: return false }
    }
}

// MARK: - Provider 模型配置

public struct ProviderModelConfig: Equatable, Sendable, Codable {
    public let reasoningEfforts: [String]?
    public let disabled: Bool

    public init(reasoningEfforts: [String]? = nil, disabled: Bool = false) {
        self.reasoningEfforts = reasoningEfforts; self.disabled = disabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reasoningEfforts = try c.decodeIfPresent([String].self, forKey: .reasoningEfforts)
        disabled = try c.decodeIfPresent(Bool.self, forKey: .disabled) ?? false
    }

    enum CodingKeys: String, CodingKey { case reasoningEfforts, disabled }
}

// MARK: - Provider 别名配置

public struct AliasConfig: Equatable, Sendable, Codable {
    public let targetModel: String
    public let reasoningEfforts: [String: String]?
    public init(targetModel: String, reasoningEfforts: [String: String]? = nil) {
        self.targetModel = targetModel; self.reasoningEfforts = reasoningEfforts
    }
    enum CodingKeys: String, CodingKey { case targetModel = "as", reasoningEfforts }
}

// MARK: - Provider 配置

public struct ProviderConfig: Equatable, Sendable, Codable {
    public let name: String
    public let type: ProviderType
    public let baseURL: String
    public let apiKey: String
    public let disabled: Bool
    public let models: [String: ProviderModelConfig]?
    public let aliases: [String: AliasConfig]?

    public init(name: String, type: ProviderType, baseURL: String, apiKey: String, disabled: Bool = false, models: [String: ProviderModelConfig]? = nil, aliases: [String: AliasConfig]? = nil) {
        self.name = name; self.type = type; self.baseURL = baseURL; self.apiKey = apiKey
        self.disabled = disabled; self.models = models; self.aliases = aliases
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        type = try c.decode(ProviderType.self, forKey: .type)
        baseURL = try c.decode(String.self, forKey: .baseURL)
        apiKey = try c.decode(String.self, forKey: .apiKey)
        disabled = try c.decodeIfPresent(Bool.self, forKey: .disabled) ?? false
        models = try c.decodeIfPresent([String: ProviderModelConfig].self, forKey: .models)
        aliases = try c.decodeIfPresent([String: AliasConfig].self, forKey: .aliases)
    }

    enum CodingKeys: String, CodingKey { case name, type, baseURL, apiKey, disabled, models, aliases }

    public var resolvedAPIKey: String {
        if apiKey.hasPrefix("env:") { let n = String(apiKey.dropFirst(4)); return ProcessInfo.processInfo.environment[n] ?? "" }
        return apiKey
    }
    public var publicModelIDs: [String] { models?.keys.sorted() ?? [] }
    public var normalizedBaseURL: String { baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL }
    public func buildUpstreamURL(path: String, query: String?) -> URL? {
        var s = normalizedBaseURL + (path.hasPrefix("/") ? path : "/\(path)")
        guard var c = URLComponents(string: s) else { return nil }
        c.percentEncodedQuery = query; return c.url
    }
}

// MARK: - 网关配置

public struct GatewayConfig: Equatable, Sendable {
    public let listen: ListenAddress
    public let auth: AuthConfig
    public let models: [String: String]
    public let providers: [ProviderConfig]

    public init(listen: ListenAddress, auth: AuthConfig, models: [String: String], providers: [ProviderConfig]) {
        self.listen = listen; self.auth = auth; self.models = models; self.providers = providers
    }

    public func provider(named name: String) -> ProviderConfig? { providers.first { $0.name == name } }

    public static func parseModelRoute(_ route: String) -> (provider: String, upstreamModel: String?)? {
        guard let i = route.firstIndex(of: "/") else { return nil }
        let p = String(route[..<i]), m = String(route[route.index(after: i)...])
        return m == "*" ? (p, nil) : (p, m)
    }

    public func resolveModelRoute(publicModel: String) -> (provider: ProviderConfig, upstreamModel: String)? {
        guard let route = models[publicModel], let parsed = Self.parseModelRoute(route) else { return nil }
        guard let pc = provider(named: parsed.provider), !pc.disabled else { return nil }
        let um = parsed.upstreamModel ?? publicModel
        if let a = pc.aliases?[publicModel] { return (pc, a.targetModel) }
        if pc.models?[um] != nil { return (pc, um) }
        return nil
    }

    public var enabledProviders: [ProviderConfig] { providers.filter { !$0.disabled } }
}
