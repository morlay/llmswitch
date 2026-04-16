import Foundation
import LLMGateway

@main
struct LLMSwitchCLIApp {
    static func main() async {
        do {
            try await run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            fputs("llmswitch: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func run(arguments: [String]) async throws {
        if arguments.contains("--help") || arguments.contains("-h") {
            print(usage)
            return
        }

        let configURL = try configURL(from: arguments)
        let verbose = arguments.contains("--verbose") || arguments.contains("-v")

        // 加载配置
        let config = try GatewayConfigLoader().load(from: configURL)

        // 确定 apiKey：配置了什么就用什么，
        // 仅 PROXY_MANAGED 时自动生成并写回 config.json
        let apiKey: String
        if config.auth.isProxyManaged {
            apiKey = generateAPIKey()
            print("已自动生成 API Key: \(apiKey)")
            let updated = GatewayConfig(
                listen: config.listen,
                auth: AuthConfig(apiKey: apiKey),
                models: config.models,
                providers: config.providers
            )
            try writeConfig(updated, to: configURL)
        } else {
            apiKey = config.auth.apiKey
        }

        let effectiveConfig = GatewayConfig(
            listen: config.listen,
            auth: AuthConfig(apiKey: apiKey),
            models: config.models,
            providers: config.providers
        )

        // 初始化运行时状态
        let initialState = GatewayRuntimeState.bootstrap(from: effectiveConfig)

        // 初始化日志（仅 stdout，verbose 时输出详细信息）
        let logger = GatewayLogger(verbose: verbose)

        // 初始化 SQLite 存储
        let storeURL =
            configURL
            .deletingLastPathComponent()
            .appendingPathComponent("cache", isDirectory: true)
            .appendingPathComponent("logs.sqlite", isDirectory: false)
        let usageStore = GatewayUsageStore(url: storeURL)
        try await usageStore.open()

        // 创建服务
        let service = GatewayService(
            config: effectiveConfig,
            state: initialState,
            logger: logger,
            usageStore: usageStore
        )

        // 启动 HTTP 服务器
        let server = GatewayHTTPServer(listenAddress: config.listen) { request, writer in
            await service.handleOutput(request, writer: writer)
        }
        try server.start()

        print("llmswitch 监听 \(config.listen.stringValue)")
        print("config: \(configURL.path)")
        print("store:  \(storeURL.path)")
        print("verbose: \(verbose ? "开启" : "关闭")")

        // 保持运行
        while true {
            try? await Task.sleep(for: .seconds(3600))
        }
    }

    private static func configURL(from arguments: [String]) throws -> URL {
        if let index = arguments.firstIndex(of: "--config") {
            let next = arguments.index(after: index)
            guard next < arguments.endIndex else {
                throw CLIUsageError("--config 缺少路径")
            }
            return URL(fileURLWithPath: arguments[next])
        }

        if let value = ProcessInfo.processInfo.environment["LLMSWITCH_CONFIG"], !value.isEmpty {
            return URL(fileURLWithPath: value)
        }

        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("llmswitch", isDirectory: true)
            .appendingPathComponent("config.json", isDirectory: false)
    }

    /// 生成随机 API Key
    private static func generateAPIKey() -> String {
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255) }
        let hex = bytes.map { String(format: "%02x", $0) }.joined()
        return "sk-\(hex)"
    }

    /// 将有效配置序列化写回 config.json（去掉注释的纯 JSON）
    private static func writeConfig(_ config: GatewayConfig, to url: URL) throws {
        let json: [String: Any] = [
            "listen": ["host": config.listen.host, "port": config.listen.port],
            "auth": ["apiKey": config.auth.apiKey],
            "models": config.models,
            "providers": config.providers.map { provider in
                var p: [String: Any] = [
                    "name": provider.name,
                    "type": provider.type.rawValue,
                    "baseURL": provider.baseURL,
                    "apiKey": provider.apiKey,
                    "disabled": provider.disabled,
                ]
                if let models = provider.models {
                    p["models"] = models.mapValues { modelConfig in
                        var m: [String: Any] = [:]
                        if let efforts = modelConfig.reasoningEfforts {
                            m["reasoningEfforts"] = efforts
                        }
                        return m
                    }
                }
                if let aliases = provider.aliases {
                    p["aliases"] = aliases.mapValues { alias in
                        var a: [String: Any] = ["as": alias.targetModel]
                        if let mapping = alias.reasoningEfforts {
                            a["reasoningEfforts"] = mapping
                        }
                        return a
                    }
                }
                return p
            },
        ]
        let data = try JSONSerialization.data(
            withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private static let usage = """
        用法:
          llmswitch --config <path> [--verbose]

        环境变量:
          LLMSWITCH_CONFIG

        默认配置:
          ~/.config/llmswitch/config.json

        配置示例见 .tmp/config.example.jsonc
        """
}

private struct CLIUsageError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
