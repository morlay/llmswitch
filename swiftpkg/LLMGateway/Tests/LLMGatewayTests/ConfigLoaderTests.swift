import Foundation
import Testing

@testable import LLMGateway

@Suite struct ConfigLoaderTests {

    // MARK: - JSON 注释去除

    @Test func 去除单行注释() {
        let input = """
            {
                // 这是注释
                "key": "value"
            }
            """
        let stripped = GatewayConfigLoader.stripJSONComments(from: input)
        #expect(!stripped.contains("这是注释"))
        #expect(stripped.contains("\"key\""))
        #expect(stripped.contains("\"value\""))
    }

    @Test func 去除块注释() {
        let input = """
            {
                /* 块注释 */
                "key": "value"
            }
            """
        let stripped = GatewayConfigLoader.stripJSONComments(from: input)
        #expect(!stripped.contains("块注释"))
        #expect(stripped.contains("\"key\""))
    }

    @Test func 保留字符串内的双斜杠() {
        let input = """
            {
                "url": "https://example.com/path"
            }
            """
        let stripped = GatewayConfigLoader.stripJSONComments(from: input)
        #expect(stripped.contains("https://example.com/path"))
    }

    @Test func 保留字符串内的井号() {
        let input = """
            {
                "comment": "this is # not a comment"
            }
            """
        let stripped = GatewayConfigLoader.stripJSONComments(from: input)
        #expect(stripped.contains("this is # not a comment"))
    }

    // MARK: - 配置解析

    @Test func 解析完整配置() throws {
        let json = """
            {
                "listen": { "host": "127.0.0.1", "port": 8087 },
                "auth": { "apiKey": "sk-test-key" },
                "models": {
                    "gpt-5.5": "provider0/*",
                    "gpt-5.4-mini": "deepseek/*"
                },
                "providers": [
                    {
                        "name": "provider0",
                        "type": "openai",
                        "baseURL": "https://api.mock-provider0.test",
                        "apiKey": "env:LLM_MOCK_KEY",
                        "disabled": false,
                        "models": {
                            "gpt-5.5": { "reasoningEfforts": ["medium", "xhigh"] }
                        }
                    },
                    {
                        "name": "deepseek",
                        "type": "openai-compatible",
                        "baseURL": "https://api.mock-deepseek.test",
                        "apiKey": "env:LLM_MOCK_KEY",
                        "disabled": false,
                        "models": {
                            "deepseek-v4-pro": {}
                        },
                        "aliases": {
                            "gpt-5.5": {
                                "as": "deepseek-v4-pro",
                                "reasoningEfforts": { "medium": "high" }
                            }
                        }
                    }
                ]
            }
            """

        let config = try GatewayConfigLoader().parse(json)

        #expect(config.listen.host == "127.0.0.1")
        #expect(config.listen.port == 8087)
        #expect(config.auth.apiKey == "sk-test-key")
        #expect(config.models["gpt-5.5"] == "provider0/*")
        #expect(config.models["gpt-5.4-mini"] == "deepseek/*")
        #expect(config.providers.count == 2)

        let deepseek = config.provider(named: "deepseek")
        #expect(deepseek != nil)
        #expect(deepseek?.type == .openaiCompatible)
        #expect(deepseek?.aliases?["gpt-5.5"]?.targetModel == "deepseek-v4-pro")
        #expect(deepseek?.aliases?["gpt-5.5"]?.reasoningEfforts?["medium"] == "high")
    }

    @Test func 解析PROXY_MANAGED鉴权() throws {
        let json = """
            {
                "listen": { "host": "0.0.0.0", "port": 9000 },
                "auth": { "apiKey": "PROXY_MANAGED" },
                "models": {},
                "providers": []
            }
            """
        let config = try GatewayConfigLoader().parse(json)
        #expect(config.auth.isProxyManaged == true)
    }

    @Test func 解析env前缀APIKey() throws {
        setenv("TEST_ENV_KEY", "env-resolved-value", 1)
        let json = """
            {
                "listen": { "host": "0.0.0.0", "port": 9000 },
                "auth": { "apiKey": "sk-fixed" },
                "models": {},
                "providers": [
                    {
                        "name": "test",
                        "type": "openai",
                        "baseURL": "https://test.example.com",
                        "apiKey": "env:TEST_ENV_KEY",
                        "disabled": false
                    }
                ]
            }
            """
        let config = try GatewayConfigLoader().parse(json)
        let provider = config.provider(named: "test")
        #expect(provider?.apiKey == "env:TEST_ENV_KEY")
        #expect(provider?.resolvedAPIKey == "env-resolved-value")
    }

    @Test func 解析无效端口抛出错误() {
        let json = """
            {
                "listen": { "host": "", "port": 99999 },
                "auth": { "apiKey": "sk-test" },
                "models": {},
                "providers": []
            }
            """
        #expect(throws: ConfigLoadError.self) {
            try GatewayConfigLoader().parse(json)
        }
    }

    @Test func 解析无效模型路由抛出错误() {
        let json = """
            {
                "listen": { "host": "127.0.0.1", "port": 8080 },
                "auth": { "apiKey": "sk-test" },
                "models": { "bad-model": "invalid-route-without-slash" },
                "providers": []
            }
            """
        #expect(throws: ConfigLoadError.self) {
            try GatewayConfigLoader().parse(json)
        }
    }

    @Test func 解析无效Provider类型抛出错误() {
        let json = """
            {
                "listen": { "host": "127.0.0.1", "port": 8080 },
                "auth": { "apiKey": "sk-test" },
                "models": {},
                "providers": [
                    {
                        "name": "bad",
                        "type": "unknown-type",
                        "baseURL": "https://example.com",
                        "apiKey": "sk-test",
                        "disabled": false
                    }
                ]
            }
            """
        #expect(throws: ConfigLoadError.self) {
            try GatewayConfigLoader().parse(json)
        }
    }
}
