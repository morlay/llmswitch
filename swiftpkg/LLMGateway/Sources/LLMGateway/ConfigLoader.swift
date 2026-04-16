import Foundation

// MARK: - 配置加载错误

public enum ConfigLoadError: LocalizedError, Sendable {
    case fileNotFound(URL)
    case invalidJSON(String)
    case missingKey(String)
    case invalidType(String)
    case invalidListenAddress(String)
    case invalidModelRoute(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "配置文件不存在: \(url.path)"
        case .invalidJSON(let message):
            return "JSON 解析失败: \(message)"
        case .missingKey(let key):
            return "缺少必需配置项: \(key)"
        case .invalidType(let key):
            return "配置项类型错误: \(key)"
        case .invalidListenAddress(let value):
            return "无效的监听地址: \(value)"
        case .invalidModelRoute(let route):
            return "无效的模型路由: \(route)"
        }
    }
}

// MARK: - JSON 原始类型（用于中间解码）

private struct RawListenConfig: Decodable {
    let host: String
    let port: Int
}

private struct RawAuthConfig: Decodable {
    let apiKey: String
}

private struct RawProviderModelConfig: Decodable {
    let reasoningEfforts: [String]?
    var disabled: Bool = false
    
    enum CodingKeys: String, CodingKey { case reasoningEfforts, disabled }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reasoningEfforts = try c.decodeIfPresent([String].self, forKey: .reasoningEfforts)
        disabled = try c.decodeIfPresent(Bool.self, forKey: .disabled) ?? false
    }
}

private struct RawAliasConfig: Decodable {
    let targetModel: String
    let reasoningEfforts: [String: String]?

    enum CodingKeys: String, CodingKey {
        case targetModel = "as"
        case reasoningEfforts
    }
}

private struct RawProviderConfig: Decodable {
    let name: String
    let type: String
    let baseURL: String
    let apiKey: String
    var disabled: Bool = false
    let models: [String: RawProviderModelConfig]?
    let aliases: [String: RawAliasConfig]?
    
    enum CodingKeys: String, CodingKey {
        case name, type, baseURL, apiKey, disabled, models, aliases
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        type = try c.decode(String.self, forKey: .type)
        baseURL = try c.decode(String.self, forKey: .baseURL)
        apiKey = try c.decode(String.self, forKey: .apiKey)
        disabled = try c.decodeIfPresent(Bool.self, forKey: .disabled) ?? false
        models = try c.decodeIfPresent([String: RawProviderModelConfig].self, forKey: .models)
        aliases = try c.decodeIfPresent([String: RawAliasConfig].self, forKey: .aliases)
    }
}

private struct RawGatewayConfig: Decodable {
    let listen: RawListenConfig
    let auth: RawAuthConfig
    let models: [String: String]
    let providers: [RawProviderConfig]
}

// MARK: - 配置加载器

public struct GatewayConfigLoader: Sendable {

    public init() {}

    /// 从 URL 加载配置（支持 JSONC → 自动去注释）
    public func load(from url: URL) throws -> GatewayConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ConfigLoadError.fileNotFound(url)
        }

        let raw = try String(contentsOf: url, encoding: .utf8)
        let stripped = Self.stripJSONComments(from: raw)

        guard let data = stripped.data(using: .utf8) else {
            throw ConfigLoadError.invalidJSON("无法编码为 UTF-8")
        }

        let decoder = JSONDecoder()
        let rawConfig: RawGatewayConfig
        do {
            rawConfig = try decoder.decode(RawGatewayConfig.self, from: data)
        } catch {
            throw ConfigLoadError.invalidJSON(error.localizedDescription)
        }

        return try Self.transform(rawConfig)
    }

    /// 从 JSON 字符串直接解析（供测试用）
    public func parse(_ jsonString: String) throws -> GatewayConfig {
        let stripped = Self.stripJSONComments(from: jsonString)
        guard let data = stripped.data(using: .utf8) else {
            throw ConfigLoadError.invalidJSON("无法编码为 UTF-8")
        }
        let decoder = JSONDecoder()
        let rawConfig = try decoder.decode(RawGatewayConfig.self, from: data)
        return try Self.transform(rawConfig)
    }

    // MARK: - 私有方法

    private static func transform(_ raw: RawGatewayConfig) throws -> GatewayConfig {
        // 解析 listen
        guard (1...65535).contains(raw.listen.port), !raw.listen.host.isEmpty else {
            throw ConfigLoadError.invalidListenAddress("\(raw.listen.host):\(raw.listen.port)")
        }
        let listen = ListenAddress(host: raw.listen.host, port: raw.listen.port)

        // 解析 auth
        let auth = AuthConfig(apiKey: raw.auth.apiKey)

        // 验证模型路由表
        for (model, route) in raw.models {
            guard GatewayConfig.parseModelRoute(route) != nil else {
                throw ConfigLoadError.invalidModelRoute("\(model) -> \(route)")
            }
        }

        // 解析 providers
        let providers: [ProviderConfig] = try raw.providers.map { rawProvider in
            guard let providerType = ProviderType(rawValue: rawProvider.type) else {
                throw ConfigLoadError.invalidType(
                    "providers[\(rawProvider.name)].type: 不支持的类型 '\(rawProvider.type)'")
            }

            let models: [String: ProviderModelConfig]? = rawProvider.models?.mapValues {
                ProviderModelConfig(reasoningEfforts: $0.reasoningEfforts)
            }

            let aliases: [String: AliasConfig]? = rawProvider.aliases?.mapValues {
                AliasConfig(targetModel: $0.targetModel, reasoningEfforts: $0.reasoningEfforts)
            }

            return ProviderConfig(
                name: rawProvider.name,
                type: providerType,
                baseURL: rawProvider.baseURL,
                apiKey: rawProvider.apiKey,
                disabled: rawProvider.disabled,
                models: models,
                aliases: aliases
            )
        }

        return GatewayConfig(
            listen: listen,
            auth: auth,
            models: raw.models,
            providers: providers
        )
    }

    /// 去除 JSON 中的 // 单行注释
    public static func stripJSONComments(from source: String) -> String {
        var result = ""
        var inString = false
        var isEscaped = false
        var inLineComment = false
        var inBlockComment = false
        var previousChar: Character?

        for char in source {
            if inLineComment {
                if char == "\n" || char == "\r" {
                    inLineComment = false
                    result.append(char)
                }
                continue
            }

            if inBlockComment {
                if previousChar == "*" && char == "/" {
                    inBlockComment = false
                    previousChar = nil
                } else {
                    previousChar = char
                }
                continue
            }

            if isEscaped {
                result.append(char)
                isEscaped = false
                continue
            }

            if char == "\\" && inString {
                result.append(char)
                isEscaped = true
                continue
            }

            if char == "\"" {
                inString.toggle()
                result.append(char)
                continue
            }

            if !inString {
                if char == "/" && previousChar == "/" {
                    // 移除刚追加的 /
                    result.removeLast()
                    inLineComment = true
                    previousChar = nil
                    continue
                }
                if char == "*" && previousChar == "/" {
                    // 移除刚追加的 /
                    result.removeLast()
                    inBlockComment = true
                    previousChar = nil
                    continue
                }
            }

            result.append(char)
            previousChar = char
        }

        return result
    }
}
