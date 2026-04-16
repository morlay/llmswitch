import Foundation
import Testing
@testable import LLMSwitchCore

@Test func registryUsesExplicitBindingBeforeFallback() {
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
                displayName: "OpenAI",
                baseURL: URL(string: "https://api.openai.com")!,
                apiKey: "openai-key",
                enabled: true
            ),
            "mirror": ProviderConfig(
                name: "mirror",
                displayName: "Mirror",
                baseURL: URL(string: "https://mirror.example.com")!,
                apiKey: "mirror-key",
                enabled: true
            ),
        ]
    )

    let state = AppState(
        enabledProviderModels: [
            "openai": [
                "mirror-model": true,
            ],
            "mirror": [
                "gpt-4.1": true,
            ],
        ],
        activeBindings: [
            "gpt-4.1": ActiveBinding(provider: "mirror", upstreamModel: "gpt-4.1"),
        ]
    )

    let snapshots = [
        "openai": ProviderCacheSnapshot(
            meta: ProviderCacheMeta(providerName: "openai", fetchedAt: Date(), wasSuccessful: true, errorMessage: nil),
            models: [ProviderModel(id: "gpt-4.1"), ProviderModel(id: "mirror-model")]
        ),
        "mirror": ProviderCacheSnapshot(
            meta: ProviderCacheMeta(providerName: "mirror", fetchedAt: Date(), wasSuccessful: true, errorMessage: nil),
            models: [ProviderModel(id: "gpt-4.1")]
        ),
    ]

    let registry = ModelRegistry(config: config, state: state, snapshots: snapshots)

    #expect(registry.resolve(modelName: "gpt-4.1")?.providerName == "mirror")
    #expect(registry.resolve(modelName: "mirror-model")?.providerName == "openai")
}

@Test func registryListsOnlyResolvableModels() {
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
            "mirror": ProviderConfig(
                name: "mirror",
                displayName: "Mirror",
                baseURL: URL(string: "https://mirror.example.com")!,
                apiKey: "mirror-key",
                enabled: true
            ),
        ]
    )

    let state = AppState(
        enabledProviderModels: [
            "openai": [
                "gpt-4.1": true,
                "o1-mini": true,
            ],
            "mirror": [
                "gpt-4.1": true,
            ],
        ]
    )

    let snapshots = [
        "openai": ProviderCacheSnapshot(
            meta: ProviderCacheMeta(providerName: "openai", fetchedAt: Date(), wasSuccessful: true, errorMessage: nil),
            models: [ProviderModel(id: "gpt-4.1"), ProviderModel(id: "o1-mini")]
        ),
        "mirror": ProviderCacheSnapshot(
            meta: ProviderCacheMeta(providerName: "mirror", fetchedAt: Date(), wasSuccessful: true, errorMessage: nil),
            models: [ProviderModel(id: "gpt-4.1")]
        ),
    ]

    let unresolvedRegistry = ModelRegistry(config: config, state: state, snapshots: snapshots)
    #expect(unresolvedRegistry.listModels().map(\.publicName) == ["o1-mini"])

    let resolvedState = AppState(
        enabledProviderModels: state.enabledProviderModels,
        activeBindings: [
            "gpt-4.1": ActiveBinding(provider: "mirror", upstreamModel: "gpt-4.1"),
        ]
    )
    let resolvedRegistry = ModelRegistry(config: config, state: resolvedState, snapshots: snapshots)
    #expect(resolvedRegistry.listModels().map(\.publicName) == ["gpt-4.1", "o1-mini"])
}
