import Foundation
import LLMGateway

@MainActor
final class ConfigStore: ObservableObject {
    private let paths: AppPaths

    @Published var effectiveConfig: GatewayConfig = .empty
    @Published var runtimeState: GatewayRuntimeState = .init()

    init(paths: AppPaths) {
        self.paths = paths
    }

    func ensureConfigExists() throws {
        try FileManager.default.createDirectory(
            at: paths.configRoot, withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: paths.configFile.path) else { return }
        let empty = GatewayConfig.empty
        let data = try JSONSerialization.data(
            withJSONObject: empty.asJSON(), options: .prettyPrinted)
        try data.write(to: paths.configFile, options: .atomic)
    }

    func loadConfig() throws {
        let loader = GatewayConfigLoader()
        let config = try loader.load(from: paths.configFile)
        effectiveConfig = config
    }

    func saveConfig(_ config: GatewayConfig) throws {
        let data = try JSONSerialization.data(
            withJSONObject: config.asJSON(), options: [.prettyPrinted, .withoutEscapingSlashes])
        try data.write(to: paths.configFile, options: .atomic)
        effectiveConfig = config
    }

    func loadState() throws {
        runtimeState = GatewayRuntimeState.bootstrap(from: effectiveConfig)
    }
}

extension GatewayConfig {
    static let empty = GatewayConfig(
        listen: ListenAddress(host: "127.0.0.1", port: 8087),
        auth: AuthConfig(apiKey: "PROXY_MANAGED"),
        models: [:],
        providers: []
    )

    func asJSON() -> [String: Any] {
        [
            "listen": ["host": listen.host, "port": listen.port],
            "auth": ["apiKey": auth.apiKey],
            "models": models,
            "providers": providers.map { p in
                var dict: [String: Any] = [
                    "name": p.name, "type": p.type.rawValue,
                    "baseURL": p.baseURL, "apiKey": p.apiKey
                ]
                if p.disabled { dict["disabled"] = true }
                if let m = p.models {
                    dict["models"] = m.mapValues {
                        ["reasoningEfforts": $0.reasoningEfforts as Any]
                    }
                }
                if let a = p.aliases {
                    dict["aliases"] = a.mapValues {
                        ["as": $0.targetModel, "reasoningEfforts": $0.reasoningEfforts as Any]
                    }
                }
                return dict
            },
        ]
    }
}
