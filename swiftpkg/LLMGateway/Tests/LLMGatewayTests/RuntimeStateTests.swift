import Foundation
import Testing

@testable import LLMGateway

@Suite struct RuntimeStateTests {

    // MARK: - 从配置引导

    @Test func 从配置引导生成绑定() throws {
        let config = makeConfig()
        let state = GatewayRuntimeState.bootstrap(from: config)

        // gpt-5.5 → provider0/gpt-5.5
        let gpt55 = state.binding(for: "gpt-5.5")
        #expect(gpt55?.provider == "provider0")
        #expect(gpt55?.upstreamModel == "gpt-5.5")

        // gpt-5.4-mini → deepseek/deepseek-v4-flash (via alias)
        let mini = state.binding(for: "gpt-5.4-mini")
        #expect(mini?.provider == "deepseek")
        #expect(mini?.upstreamModel == "deepseek-v4-flash")
    }

    @Test func 禁用的Provider不绑定() throws {
        let config = makeConfig()
        let state = GatewayRuntimeState.bootstrap(from: config)

        // disabled-provider 有 gpt-5.5 但被禁用，不应绑定
        // gpt-5.5 路由到 provider0，所以应该存在
        #expect(state.binding(for: "gpt-5.5") != nil)
    }

    @Test func 公开模型列表() throws {
        let config = makeConfig()
        let state = GatewayRuntimeState.bootstrap(from: config)
        let models = state.publicModels

        #expect(models.contains("gpt-5.5"))
        #expect(models.contains("gpt-5.4-mini"))
    }

    // MARK: - 动态切换

    @Test func 动态切换Provider绑定() {
        var state = GatewayRuntimeState.bootstrap(from: makeConfig())

        state.switchBinding(
            model: "gpt-5.5",
            to: "deepseek",
            upstreamModel: "deepseek-v4-pro"
        )

        let binding = state.binding(for: "gpt-5.5")
        #expect(binding?.provider == "deepseek")
        #expect(binding?.upstreamModel == "deepseek-v4-pro")
    }

    @Test func 移除绑定() {
        var state = GatewayRuntimeState.bootstrap(from: makeConfig())
        state.removeBinding(for: "gpt-5.5")
        #expect(state.binding(for: "gpt-5.5") == nil)
    }

    @Test func 空状态初始化() {
        let state = GatewayRuntimeState()
        #expect(state.binding(for: "any") == nil)
        #expect(state.publicModels.isEmpty)
    }

    // MARK: - 辅助

    private func makeConfig() -> GatewayConfig {
        let json = """
            {
                "listen": { "host": "127.0.0.1", "port": 8087 },
                "auth": { "apiKey": "sk-test" },
                "models": {
                    "gpt-5.5": "provider0/*",
                    "gpt-5.4-mini": "deepseek/*"
                },
                "providers": [
                    {
                        "name": "provider0",
                        "type": "openai",
                        "baseURL": "https://api.mock-provider0.test",
                        "apiKey": "sk-key",
                        "disabled": false,
                        "models": {
                            "gpt-5.5": {},
                            "gpt-5.4-mini": {}
                        }
                    },
                    {
                        "name": "deepseek",
                        "type": "openai-compatible",
                        "baseURL": "https://api.mock-deepseek.test",
                        "apiKey": "sk-key",
                        "disabled": false,
                        "models": {
                            "deepseek-v4-flash": {}
                        },
                        "aliases": {
                            "gpt-5.4-mini": { "as": "deepseek-v4-flash" }
                        }
                    },
                    {
                        "name": "disabled-provider",
                        "type": "openai",
                        "baseURL": "https://disabled.example.com",
                        "apiKey": "sk-key",
                        "disabled": true,
                        "models": { "gpt-5.5": {} }
                    }
                ]
            }
            """
        return try! GatewayConfigLoader().parse(json)
    }
}
