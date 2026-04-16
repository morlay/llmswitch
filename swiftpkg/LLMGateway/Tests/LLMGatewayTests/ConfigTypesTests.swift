import Foundation
import Testing

@testable import LLMGateway

@Suite struct ConfigTypesTests {

    // MARK: - 模型路由解析

    @Test func 解析通配符路由() {
        let result = GatewayConfig.parseModelRoute("provider0/*")
        #expect(result?.provider == "provider0")
        #expect(result?.upstreamModel == nil)
    }

    @Test func 解析指定上游模型路由() {
        let result = GatewayConfig.parseModelRoute("deepseek/deepseek-v4-pro")
        #expect(result?.provider == "deepseek")
        #expect(result?.upstreamModel == "deepseek-v4-pro")
    }

    @Test func 无效路由返回nil() {
        #expect(GatewayConfig.parseModelRoute("invalid-route") == nil)
        #expect(GatewayConfig.parseModelRoute("") == nil)
    }

    // MARK: - 模型路由解析到 Provider

    @Test func 解析到启用的Provider() throws {
        let config = makeConfig()
        let result = config.resolveModelRoute(publicModel: "gpt-5.5")
        #expect(result != nil)
        #expect(result?.provider.name == "provider0")
        #expect(result?.upstreamModel == "gpt-5.5")
    }

    @Test func 解析到带别名的Provider() throws {
        let config = makeConfig()
        let result = config.resolveModelRoute(publicModel: "gpt-5.4-mini")
        #expect(result != nil)
        #expect(result?.provider.name == "deepseek")
        #expect(result?.upstreamModel == "deepseek-v4-flash")
    }

    @Test func 未配置的模型返回nil() throws {
        let config = makeConfig()
        #expect(config.resolveModelRoute(publicModel: "unknown-model") == nil)
    }

    @Test func 禁用的Provider不参与路由() throws {
        let config = makeConfig()
        // gpt-5.4 只路由到 provider0，没有其他 provider
        let result = config.resolveModelRoute(publicModel: "gpt-5.4")
        #expect(result?.provider.name == "provider0")
        #expect(result?.upstreamModel == "gpt-5.4")
    }

    // MARK: - Provider 类型

    @Test func openai类型支持Responses() {
        #expect(ProviderType.openai.supportsResponses == true)
    }

    @Test func openaiCompatible类型不支持Responses() {
        #expect(ProviderType.openaiCompatible.supportsResponses == false)
    }

    // MARK: - API Key 解析

    @Test func 明文APIKey直接返回() {
        let provider = ProviderConfig(
            name: "test",
            type: .openai,
            baseURL: "https://test.com",
            apiKey: "sk-plain-key",
            disabled: false
        )
        #expect(provider.resolvedAPIKey == "sk-plain-key")
    }

    @Test func env前缀APIKey从环境变量解析() {
        setenv("TEST_PROVIDER_KEY", "env-value-123", 1)
        let provider = ProviderConfig(
            name: "test",
            type: .openai,
            baseURL: "https://test.com",
            apiKey: "env:TEST_PROVIDER_KEY",
            disabled: false
        )
        #expect(provider.resolvedAPIKey == "env-value-123")
    }

    // MARK: - 上游 URL 构建

    @Test func 构建上游URL包含路径() {
        let provider = ProviderConfig(
            name: "test",
            type: .openai,
            baseURL: "https://api.test.com",
            apiKey: "sk-key",
            disabled: false
        )
        let url = provider.buildUpstreamURL(path: "/v1/chat/completions", query: nil)
        #expect(url?.absoluteString == "https://api.test.com/v1/chat/completions")
    }

    @Test func 构建上游URL包含查询参数() {
        let provider = ProviderConfig(
            name: "test",
            type: .openai,
            baseURL: "https://api.test.com/",
            apiKey: "sk-key",
            disabled: false
        )
        let url = provider.buildUpstreamURL(path: "/v1/models", query: "filter=active")
        #expect(url?.absoluteString == "https://api.test.com/v1/models?filter=active")
    }

    // MARK: - 辅助

    private func makeConfig() -> GatewayConfig {
        let json = """
            {
                "listen": { "host": "127.0.0.1", "port": 8087 },
                "auth": { "apiKey": "sk-test" },
                "models": {
                    "gpt-5.5": "provider0/*",
                    "gpt-5.4": "provider0/*",
                    "gpt-5.4-mini": "deepseek/*"
                },
                "providers": [
                    {
                        "name": "provider0",
                        "type": "openai",
                        "baseURL": "https://api.mock-provider0.test",
                        "apiKey": "sk-provider0-key",
                        "disabled": false,
                        "models": {
                            "gpt-5.5": {},
                            "gpt-5.4": {},
                            "gpt-5.4-mini": {}
                        }
                    },
                    {
                        "name": "deepseek",
                        "type": "openai-compatible",
                        "baseURL": "https://api.mock-deepseek.test",
                        "apiKey": "sk-deepseek-key",
                        "disabled": false,
                        "models": {
                            "deepseek-v4-flash": {},
                            "deepseek-v4-pro": {}
                        },
                        "aliases": {
                            "gpt-5.4-mini": { "as": "deepseek-v4-flash" }
                        }
                    },
                    {
                        "name": "disabled-provider",
                        "type": "openai",
                        "baseURL": "https://disabled.example.com",
                        "apiKey": "sk-disabled",
                        "disabled": true,
                        "models": {}
                    }
                ]
            }
            """
        return try! GatewayConfigLoader().parse(json)
    }
}
