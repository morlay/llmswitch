import Foundation
import Testing
@testable import LLMSwitchCore

@Test func configAndStateDecode() throws {
    let source = """
    [app]
    listen = "127.0.0.1:8787"
    modelRefreshIntervalSeconds = 300
    requestTimeoutSeconds = 600
    apiKey = "local-api-key"

    [providers.openai]
    baseUrl = "https://api.openai.com"
    apiKey = "openai-key"
    enabled = true

    [providers.local]
    displayName = "Local"
    baseUrl = "http://127.0.0.1:11434"
    apiKey = "dev-token"
    enabled = false
    """

    let config = try ConfigStore.decode(document: TOMLParser.parse(source))
    #expect(config.app.listen == "127.0.0.1:8787")
    #expect(config.app.apiKey == "local-api-key")
    #expect(config.providers["openai"]?.resolvedDisplayName == "openai")
    #expect(config.providers["openai"]?.apiKey == "openai-key")
    #expect(config.providers["local"]?.enabled == false)

    let stateSource = """
    [enabledProviderModels.openai]
    "gpt-4.1" = true

    [enabledProviderModels.deepseek]
    "deepseek-chat" = true

    [activeBindings."gpt-4.1"]
    provider = "openai"
    upstreamModel = "gpt-4.1"

    [activeBindings."deepseek-chat"]
    provider = "deepseek"
    upstreamModel = "deepseek-chat"
    """

    let tmpDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tmpDirectory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: tmpDirectory)
    }

    let paths = AppPaths(configRoot: tmpDirectory)
    try stateSource.write(to: paths.stateFile, atomically: true, encoding: .utf8)

    let state = try StateStore(paths: paths).load()
    #expect(state.enabledProviderModels["openai"]?["gpt-4.1"] == true)
    #expect(state.activeBindings["gpt-4.1"] == ActiveBinding(provider: "openai", upstreamModel: "gpt-4.1"))
}

@Test func stateRoundTrips() throws {
    let state = AppState(
        enabledProviderModels: [
            "deepseek": ["deepseek-chat": true],
            "openai": ["gpt-4.1": true],
        ],
        activeBindings: [
            "deepseek-chat": ActiveBinding(provider: "deepseek", upstreamModel: "deepseek-chat")
        ]
    )

    let serialized = state.serialized()
    let tmpDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tmpDirectory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: tmpDirectory)
    }

    let paths = AppPaths(configRoot: tmpDirectory)
    try serialized.write(to: paths.stateFile, atomically: true, encoding: .utf8)

    let decoded = try StateStore(paths: paths).load()
    #expect(decoded == state)
}

@Test func configRoundTripsWithOptionalDisplayName() throws {
    let config = AppConfig(
        app: AppSettings(
            listenAddress: ListenAddress(host: "127.0.0.1", port: 8787),
            modelRefreshIntervalSeconds: 300,
            requestTimeoutSeconds: 600,
            apiKey: "service-key"
        ),
        providers: [
            "openai": ProviderConfig(
                name: "openai",
                displayName: nil,
                baseURL: URL(string: "https://api.openai.com")!,
                apiKey: "openai-key",
                enabled: true
            ),
            "deepseek": ProviderConfig(
                name: "deepseek",
                displayName: "DeepSeek",
                baseURL: URL(string: "https://api.deepseek.com")!,
                apiKey: "deepseek-key",
                enabled: false
            ),
        ]
    )

    let serialized = ConfigStore.serialize(config)
    let decoded = try ConfigStore.decode(document: TOMLParser.parse(serialized))

    #expect(decoded == config)
}
