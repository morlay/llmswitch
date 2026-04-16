import Foundation
import Testing

@testable import LLMGateway

@Suite struct UsageStoreTests {

    // MARK: - Token 用量记录

    @Test func 记录和查询用量汇总() async throws {
        let store = try await makeStore()

        try await store.recordUsage(
            TokenUsageRecord(
                model: "gpt-5.5", provider: "openai", endpoint: "/v1/chat/completions",
                statusCode: 200, latencyMs: 100,
                promptTokens: 10, completionTokens: 20, totalTokens: 30
            ))
        try await store.recordUsage(
            TokenUsageRecord(
                model: "gpt-5.5", provider: "openai", endpoint: "/v1/chat/completions",
                statusCode: 200, latencyMs: 200,
                promptTokens: 5, completionTokens: 15, totalTokens: 20
            ))
        try await store.recordUsage(
            TokenUsageRecord(
                model: "gpt-5.4", provider: "deepseek", endpoint: "/v1/responses",
                statusCode: 200, latencyMs: 150,
                promptTokens: 20, completionTokens: 30, totalTokens: 50
            ))

        let summary = try await store.queryUsageSummary()
        #expect(summary.totalRequests == 3)
        #expect(summary.totalPromptTokens == 35)
        #expect(summary.totalCompletionTokens == 65)
        #expect(summary.totalTokens == 100)
    }

    @Test func 按模型分组查询() async throws {
        let store = try await makeStore()

        try await store.recordUsage(
            TokenUsageRecord(
                model: "gpt-5.5", provider: "openai", endpoint: "/v1/chat/completions",
                statusCode: 200, latencyMs: 100,
                promptTokens: 10, completionTokens: 10, totalTokens: 20
            ))
        try await store.recordUsage(
            TokenUsageRecord(
                model: "gpt-5.4", provider: "deepseek", endpoint: "/v1/responses",
                statusCode: 200, latencyMs: 100,
                promptTokens: 30, completionTokens: 50, totalTokens: 80
            ))

        let modelUsage = try await store.queryModelUsage()
        #expect(modelUsage.count == 2)

        let sorted = modelUsage.sorted { $0.totalTokens > $1.totalTokens }
        #expect(sorted[0].model == "gpt-5.4")
        #expect(sorted[0].totalTokens == 80)
        #expect(sorted[1].model == "gpt-5.5")
        #expect(sorted[1].totalTokens == 20)
    }

    @Test func 按Provider分组查询() async throws {
        let store = try await makeStore()

        try await store.recordUsage(
            TokenUsageRecord(
                model: "gpt-5.5", provider: "openai", endpoint: "/v1/chat/completions",
                statusCode: 200, latencyMs: 100,
                promptTokens: 10, completionTokens: 10, totalTokens: 20
            ))
        try await store.recordUsage(
            TokenUsageRecord(
                model: "gpt-5.4", provider: "deepseek", endpoint: "/v1/responses",
                statusCode: 200, latencyMs: 100,
                promptTokens: 30, completionTokens: 50, totalTokens: 80
            ))

        let providerUsage = try await store.queryProviderUsage()
        #expect(providerUsage.count == 2)

        let sorted = providerUsage.sorted { $0.totalTokens > $1.totalTokens }
        #expect(sorted[0].provider == "deepseek")
        #expect(sorted[0].totalTokens == 80)
    }

    @Test func 记录错误请求() async throws {
        let store = try await makeStore()

        try await store.recordUsage(
            TokenUsageRecord(
                model: "gpt-5.5", provider: "openai", endpoint: "/v1/chat/completions",
                statusCode: 500, latencyMs: 5000,
                promptTokens: 0, completionTokens: 0, totalTokens: 0,
                errorMessage: "上游超时"
            ))

        let summary = try await store.queryUsageSummary()
        #expect(summary.totalRequests == 1)
        #expect(summary.totalTokens == 0)
        #expect(summary.avgLatencyMs == 5000)
    }

    @Test func 记录流式请求() async throws {
        let store = try await makeStore()

        try await store.recordUsage(
            TokenUsageRecord(
                model: "gpt-5.5", provider: "openai", endpoint: "/v1/chat/completions",
                statusCode: 200, latencyMs: 300,
                stream: true
            ))

        let summary = try await store.queryUsageSummary()
        #expect(summary.totalRequests == 1)
    }

    // MARK: - 会话历史

    @Test func 保存和查找会话() async throws {
        let store = try await makeStore()

        let conv = ConversationRecord(
            responseId: "resp-001",
            previousResponseId: nil,
            model: "gpt-5.5",
            data: "{\"output\":[{\"type\":\"message\",\"content\":\"hello\"}]}"
        )
        try await store.saveConversation(conv)

        let found = try await store.findConversation(responseId: "resp-001")
        #expect(found != nil)
        #expect(found?.responseId == "resp-001")
        #expect(found?.model == "gpt-5.5")
    }

    @Test func 按previous_response_id查找() async throws {
        let store = try await makeStore()

        try await store.saveConversation(
            ConversationRecord(
                responseId: "resp-001", previousResponseId: nil,
                model: "gpt-5.5", data: "{}"
            ))
        try await store.saveConversation(
            ConversationRecord(
                responseId: "resp-002", previousResponseId: "resp-001",
                model: "gpt-5.5", data: "{}"
            ))
        try await store.saveConversation(
            ConversationRecord(
                responseId: "resp-003", previousResponseId: "resp-001",
                model: "gpt-5.5", data: "{}"
            ))

        let children = try await store.findConversationsByPrevious(responseId: "resp-001")
        #expect(children.count == 2)
    }

    @Test func 查找不存在的会话返回nil() async throws {
        let store = try await makeStore()
        let found = try await store.findConversation(responseId: "nonexistent")
        #expect(found == nil)
    }

    @Test func 查询最近会话() async throws {
        let store = try await makeStore()

        for i in 0..<5 {
            try await store.saveConversation(
                ConversationRecord(
                    responseId: "resp-00\(i)", previousResponseId: nil,
                    model: "gpt-5.5", data: "{}"
                ))
        }

        let recent = try await store.recentConversations(limit: 3)
        #expect(recent.count == 3)
    }

    // MARK: - 辅助

    private func makeStore() async throws -> GatewayUsageStore {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("llmgateway-tests-\(UUID().uuidString)")
            .appendingPathComponent("test.sqlite")
        let store = GatewayUsageStore(url: url)
        try await store.open()
        return store
    }
}
