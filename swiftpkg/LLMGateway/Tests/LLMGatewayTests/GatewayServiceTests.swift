import Foundation
import Testing

@testable import LLMGateway

@Suite struct GatewayServiceTests {

    @Test func models端点无需鉴权() async throws {
        let svc = try await makeService()
        let request = HTTPRequest(
            method: "GET", target: "/v1/models", version: "HTTP/1.1", headers: [:], body: Data())
        let capture = ResponseCapture()
        await svc.handleOutput(request, writer: capture)
        #expect(capture.statusCode == 200)

        let body = try JSONSerialization.jsonObject(with: capture.body) as! [String: Any]
        let data = body["data"] as! [[String: Any]]
        #expect(!data.isEmpty)
    }

    @Test func models端点包含路由模型和provider模型() async throws {
        let svc = try await makeService()
        let request = HTTPRequest(
            method: "GET", target: "/v1/models", version: "HTTP/1.1", headers: [:], body: Data())
        let capture = ResponseCapture()
        await svc.handleOutput(request, writer: capture)

        let body = try JSONSerialization.jsonObject(with: capture.body) as! [String: Any]
        let data = body["data"] as! [[String: Any]]
        let ids = data.compactMap { $0["id"] as? String }

        // 路由模型
        #expect(ids.contains("gpt-5.5"))
        #expect(ids.contains("gpt-5.4-mini"))
        // provider 模型
        #expect(ids.contains("provider0/gpt-5.5"))
        #expect(ids.contains("deepseek/deepseek-v4-pro"))
    }

    @Test func 缺少Authorization返回401() async throws {
        let svc = try await makeService()
        let request = HTTPRequest(
            method: "POST", target: "/v1/responses", version: "HTTP/1.1",
            headers: ["Content-Type": "application/json"],
            body: Data("{\"model\":\"gpt-5.5\",\"input\":\"hi\"}".utf8))
        let capture = ResponseCapture()
        await svc.handleOutput(request, writer: capture)
        #expect(capture.statusCode == 401)
    }

    @Test func 错误APIKey返回401() async throws {
        let svc = try await makeService()
        let request = HTTPRequest(
            method: "POST", target: "/v1/responses", version: "HTTP/1.1",
            headers: ["Content-Type": "application/json", "Authorization": "Bearer wrong-key"],
            body: Data("{\"model\":\"gpt-5.5\",\"input\":\"hi\"}".utf8))
        let capture = ResponseCapture()
        await svc.handleOutput(request, writer: capture)
        #expect(capture.statusCode == 401)
    }

    @Test func 请求未配置的模型返回404() async throws {
        let svc = try await makeService()
        let request = makeRequest(model: "unknown-model")
        let capture = ResponseCapture()
        await svc.handleOutput(request, writer: capture)
        #expect(capture.statusCode == 404)
    }

    @Test func 请求体缺少model字段返回400() async throws {
        let svc = try await makeService()
        let request = HTTPRequest(
            method: "POST", target: "/v1/responses", version: "HTTP/1.1",
            headers: ["Content-Type": "application/json", "Authorization": "Bearer sk-test"],
            body: Data("{\"input\":\"hi\"}".utf8))
        let capture = ResponseCapture()
        await svc.handleOutput(request, writer: capture)
        #expect(capture.statusCode == 400)
    }

    @Test func 不支持的HTTP方法返回405() async throws {
        let svc = try await makeService()
        let request = HTTPRequest(
            method: "DELETE", target: "/v1/models", version: "HTTP/1.1", headers: [:], body: Data())
        let capture = ResponseCapture()
        await svc.handleOutput(request, writer: capture)
        #expect(capture.statusCode == 405)
    }

    @Test func 动态切换模型绑定() async throws {
        let svc = try await makeService()
        let bindingsBefore = await svc.currentBindings
        #expect(bindingsBefore["gpt-5.5"]?.provider == "provider0")

        await svc.switchModelBinding(
            model: "gpt-5.5", to: "deepseek", upstreamModel: "deepseek-v4-pro")

        let bindingsAfter = await svc.currentBindings
        #expect(bindingsAfter["gpt-5.5"]?.provider == "deepseek")
        #expect(bindingsAfter["gpt-5.5"]?.upstreamModel == "deepseek-v4-pro")
    }

    // MARK: - 辅助

    private func makeService() async throws -> GatewayService {
        let config = makeConfig()
        let state = GatewayRuntimeState.bootstrap(from: config)
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("llmgateway-tests-\(UUID().uuidString)")
            .appendingPathComponent("test.sqlite")
        let usageStore = GatewayUsageStore(url: storeURL)
        try await usageStore.open()
        let logger = GatewayLogger(verbose: false)
        return GatewayService(config: config, state: state, logger: logger, usageStore: usageStore)
    }

    private func makeRequest(model: String) -> HTTPRequest {
        HTTPRequest(
            method: "POST", target: "/v1/responses", version: "HTTP/1.1",
            headers: ["Content-Type": "application/json", "Authorization": "Bearer sk-test"],
            body: Data("{\"model\":\"\(model)\",\"input\":\"hi\"}".utf8))
    }

    private func makeConfig() -> GatewayConfig {
        let json = """
            {
                "listen": { "host": "127.0.0.1", "port": 8087 },
                "auth": { "apiKey": "sk-test" },
                "models": { "gpt-5.5": "provider0/*", "gpt-5.4-mini": "deepseek/*" },
                "providers": [
                    { "name": "provider0", "type": "openai", "baseURL": "https://api.mock-a.test", "apiKey": "sk-a", "disabled": false, "models": { "gpt-5.5": {} } },
                    { "name": "deepseek", "type": "openai-compatible", "baseURL": "https://api.mock-b.test", "apiKey": "sk-b", "disabled": false, "models": { "deepseek-v4-pro": {} }, "aliases": { "gpt-5.4-mini": { "as": "deepseek-v4-pro" } } }
                ]
            }
            """
        return try! GatewayConfigLoader().parse(json)
    }
}

// MARK: - 响应捕获器

private final class ResponseCapture: HTTPResponseWriter, @unchecked Sendable {
    var statusCode: Int = 0
    var headers: [String: String] = [:]
    var body = Data()

    func send(statusCode: Int, headers: [String: String], body: Data) async throws {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    func startChunkedResponse(statusCode: Int, headers: [String: String]) async throws {
        self.statusCode = statusCode
        self.headers = headers
    }

    func sendChunk(_ data: Data) async throws { body.append(data) }
    func finishChunkedResponse() async throws {}
}
