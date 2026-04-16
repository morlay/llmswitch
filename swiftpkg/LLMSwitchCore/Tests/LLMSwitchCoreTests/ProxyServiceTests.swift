import Foundation
import Testing
@testable import LLMSwitchCore

@Test func proxyServiceRejectsInvalidAPIKeyForModels() async throws {
    let proxy = makeProxyService(
        snapshots: [
            "openai": ProviderCacheSnapshot(
                meta: ProviderCacheMeta(providerName: "openai", fetchedAt: Date(), wasSuccessful: true, errorMessage: nil),
                models: [ProviderModel(id: "gpt-4.1")]
            )
        ]
    )

    let request = HTTPRequest(
        method: "GET",
        target: "/v1/models",
        version: "HTTP/1.1",
        headers: ["authorization": "Bearer wrong-key"],
        body: Data()
    )

    let response = try await #require(proxy.response(for: request))
    #expect(response.statusCode == 401)
    #expect(String(data: response.body, encoding: .utf8)?.contains("invalid api key") == true)
}

@Test func proxyServiceListsEnabledModelsForAuthorizedModelsRequest() async throws {
    let proxy = makeProxyService(
        state: AppState(
            enabledProviderModels: [
                "openai": ["gpt-4.1": true]
            ]
        ),
        snapshots: [
            "openai": ProviderCacheSnapshot(
                meta: ProviderCacheMeta(providerName: "openai", fetchedAt: Date(), wasSuccessful: true, errorMessage: nil),
                models: [ProviderModel(id: "gpt-4.1")]
            )
        ]
    )

    let request = HTTPRequest(
        method: "GET",
        target: "/v1/models",
        version: "HTTP/1.1",
        headers: ["authorization": "Bearer service-key"],
        body: Data()
    )

    let response = try await #require(proxy.response(for: request))
    #expect(response.statusCode == 200)

    let payload = try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
    let data = try #require(payload["data"] as? [[String: Any]])
    #expect(data.count == 1)
    #expect(data.first?["id"] as? String == "gpt-4.1")
}

private func makeProxyService(
    state: AppState = .empty,
    snapshots: [String: ProviderCacheSnapshot]
) -> ProxyService {
    let config = AppConfig(
        app: AppSettings(
            listenAddress: ListenAddress(host: "127.0.0.1", port: 8787),
            modelRefreshIntervalSeconds: 300,
            requestTimeoutSeconds: 30,
            apiKey: "service-key"
        ),
        providers: [
            "openai": ProviderConfig(
                name: "openai",
                displayName: "OpenAI",
                baseURL: URL(string: "https://api.openai.com")!,
                apiKey: "upstream-key",
                enabled: true
            )
        ]
    )

    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    let paths = AppPaths(configRoot: tempRoot)
    let session = URLSession(configuration: .ephemeral)

    return ProxyService(
        config: config,
        state: state,
        cacheStore: CacheStore(paths: paths),
        providerClient: ProviderClient(session: session),
        session: session,
        snapshots: snapshots
    )
}
