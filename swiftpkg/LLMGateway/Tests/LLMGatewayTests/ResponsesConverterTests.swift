import Foundation
import Testing

@testable import LLMGateway

@Suite struct ResponsesConverterTests {

    let converter = ResponsesConverter()

    // MARK: - 请求转换：基础字段

    @Test func 转换字符串input为messages() throws {
        let responseBody = Data(
            """
            {"model":"gpt-5.5","input":"你好"}
            """.utf8)

        let chatBody = try converter.convertRequest(
            responseBody: responseBody,
            upstreamModel: "upstream-gpt-5.5"
        )

        let json = try JSONSerialization.jsonObject(with: chatBody) as! [String: Any]
        #expect(json["model"] as? String == "upstream-gpt-5.5")

        let messages = json["messages"] as! [[String: Any]]
        #expect(messages.count == 1)
        #expect(messages[0]["role"] as? String == "user")
        #expect(messages[0]["content"] as? String == "你好")
    }

    @Test func 转换instructions为system消息() throws {
        let responseBody = Data(
            """
            {"model":"gpt-5.5","instructions":"你是一个助手","input":"hello"}
            """.utf8)

        let chatBody = try converter.convertRequest(
            responseBody: responseBody,
            upstreamModel: "test-model"
        )

        let json = try JSONSerialization.jsonObject(with: chatBody) as! [String: Any]
        let messages = json["messages"] as! [[String: Any]]
        #expect(messages.count == 2)
        #expect(messages[0]["role"] as? String == "system")
        #expect(messages[0]["content"] as? String == "你是一个助手")
        #expect(messages[1]["role"] as? String == "user")
    }

    @Test func 转换消息数组input() throws {
        let responseBody = Data(
            """
            {"model":"gpt-5.5","input":[{"type":"message","role":"user","content":[{"type":"input_text","text":"hello world"}]}]}
            """.utf8)

        let chatBody = try converter.convertRequest(
            responseBody: responseBody,
            upstreamModel: "test-model"
        )

        let json = try JSONSerialization.jsonObject(with: chatBody) as! [String: Any]
        let messages = json["messages"] as! [[String: Any]]
        #expect(messages.count == 1)
        #expect(messages[0]["role"] as? String == "user")
        #expect(messages[0]["content"] as? String == "hello world")
    }

    @Test func 转换function_call_output为tool消息() throws {
        let responseBody = Data(
            """
            {"model":"gpt-5.5","input":[{"type":"function_call_output","call_id":"call_123","output":"result"}]}
            """.utf8)

        let chatBody = try converter.convertRequest(
            responseBody: responseBody,
            upstreamModel: "test-model"
        )

        let json = try JSONSerialization.jsonObject(with: chatBody) as! [String: Any]
        let messages = json["messages"] as! [[String: Any]]
        #expect(messages.count == 1)
        #expect(messages[0]["role"] as? String == "tool")
        #expect(messages[0]["tool_call_id"] as? String == "call_123")
        #expect(messages[0]["content"] as? String == "result")
    }

    // MARK: - 请求转换：参数映射

    @Test func 转换max_output_tokens为max_tokens() throws {
        let responseBody = Data(
            """
            {"model":"gpt-5.5","input":"hi","max_output_tokens":256}
            """.utf8)

        let chatBody = try converter.convertRequest(
            responseBody: responseBody,
            upstreamModel: "test-model"
        )

        let json = try JSONSerialization.jsonObject(with: chatBody) as! [String: Any]
        #expect(json["max_tokens"] as? Int == 256)
        #expect(json["max_output_tokens"] == nil)
    }

    @Test func 转换text_format为response_format() throws {
        let responseBody = Data(
            """
            {"model":"gpt-5.5","input":"hi","text":{"format":{"type":"json_object"}}}
            """.utf8)

        let chatBody = try converter.convertRequest(
            responseBody: responseBody,
            upstreamModel: "test-model"
        )

        let json = try JSONSerialization.jsonObject(with: chatBody) as! [String: Any]
        let rf = json["response_format"] as? [String: Any]
        #expect(rf?["type"] as? String == "json_object")
    }

    @Test func 直通tools和tool_choice() throws {
        let responseBody = Data(
            """
            {"model":"gpt-5.5","input":"hi","tools":[{"type":"function","function":{"name":"test"}}],"tool_choice":"auto"}
            """.utf8)

        let chatBody = try converter.convertRequest(
            responseBody: responseBody,
            upstreamModel: "test-model"
        )

        let json = try JSONSerialization.jsonObject(with: chatBody) as! [String: Any]
        #expect((json["tools"] as? [[String: Any]])?.count == 1)
        #expect(json["tool_choice"] as? String == "auto")
    }

    @Test func 直通temperature等参数() throws {
        let responseBody = Data(
            """
            {"model":"gpt-5.5","input":"hi","temperature":0.7,"top_p":0.9}
            """.utf8)

        let chatBody = try converter.convertRequest(
            responseBody: responseBody,
            upstreamModel: "test-model"
        )

        let json = try JSONSerialization.jsonObject(with: chatBody) as! [String: Any]
        #expect((json["temperature"] as? Double) == 0.7)
        #expect((json["top_p"] as? Double) == 0.9)
    }

    // MARK: - reasoningEffort 映射

    @Test func 映射reasoningEffort() throws {
        let responseBody = Data(
            """
            {"model":"gpt-5.5","input":"hi","reasoning":{"effort":"medium"}}
            """.utf8)

        let chatBody = try converter.convertRequest(
            responseBody: responseBody,
            upstreamModel: "test-model",
            reasoningEffortMapping: ["medium": "high", "xhigh": "max"]
        )

        let json = try JSONSerialization.jsonObject(with: chatBody) as! [String: Any]
        #expect(json["reasoning_effort"] as? String == "high")
    }

    @Test func 无映射时直接传递reasoningEffort() throws {
        let responseBody = Data(
            """
            {"model":"gpt-5.5","input":"hi","reasoning":{"effort":"medium"}}
            """.utf8)

        let chatBody = try converter.convertRequest(
            responseBody: responseBody,
            upstreamModel: "test-model"
        )

        let json = try JSONSerialization.jsonObject(with: chatBody) as! [String: Any]
        #expect(json["reasoning_effort"] as? String == "medium")
    }

    // MARK: - 响应转换（非流式）

    @Test func 转换ChatCompletion响应为Responses格式() throws {
        let chatResponseBody = Data(
            """
            {
                "id":"chatcmpl-123",
                "object":"chat.completion",
                "model":"gpt-5.5",
                "created": 1700000000,
                "choices":[{"index":0,"message":{"role":"assistant","content":"你好！"},"finish_reason":"stop"}],
                "usage":{"prompt_tokens":10,"completion_tokens":5,"total_tokens":15}
            }
            """.utf8)

        let requestBody = Data(
            """
            {"model":"gpt-5.5","input":"hello"}
            """.utf8)

        let responseId = "resp_test_001"
        let respBody = try converter.convertResponse(
            chatResponseBody: chatResponseBody,
            requestBody: requestBody,
            responseId: responseId
        )

        let json = try JSONSerialization.jsonObject(with: respBody) as! [String: Any]
        // 优先使用上游返回的 id
        #expect(json["id"] as? String == "chatcmpl-123")
        #expect(json["object"] as? String == "response")
        #expect(json["status"] as? String == "completed")
        #expect(json["created_at"] as? Int == 1_700_000_000)

        let output = json["output"] as! [[String: Any]]
        #expect(output.count >= 1)
        #expect(output[0]["type"] as? String == "message")
        #expect(output[0]["status"] as? String == "completed")

        let usage = json["usage"] as! [String: Any]
        #expect(usage["input_tokens"] as? Int == 10)
        #expect(usage["output_tokens"] as? Int == 5)
        #expect(usage["total_tokens"] as? Int == 15)
    }

    @Test func 提取token用量() throws {
        let chatResponseBody = Data(
            """
            {"id":"chatcmpl-1","object":"chat.completion","created":1,"model":"gpt-5.5","choices":[{"index":0,"message":{"role":"assistant","content":"ok"},"finish_reason":"stop"}],"usage":{"prompt_tokens":100,"completion_tokens":50,"total_tokens":150}}
            """.utf8)

        let usage = converter.extractUsage(from: chatResponseBody)
        #expect(usage?.promptTokens == 100)
        #expect(usage?.completionTokens == 50)
        #expect(usage?.totalTokens == 150)
    }

    // MARK: - SSE 事件转换

    @Test func 转换SSE文本增量事件() {
        var converter = ResponsesConverter()
        let sseData =
            "data: {\"id\":\"chatcmpl-1\",\"model\":\"gpt-5.5\",\"choices\":[{\"delta\":{\"content\":\"你好\"},\"index\":0}]}"
        let events = converter.convertSSEEvent(sseData, responseId: "resp-001", model: "gpt-5.5")
        // 第一个事件为 response.created
        #expect(events.count >= 1)
        #expect(events[0].contains("response.created"))
        // 包含 output_text.delta 和内容
        #expect(events.contains { $0.contains("response.output_text.delta") })
        #expect(events.contains { $0.contains("你好") })
    }

    @Test func DONE事件返回空() {
        var converter = ResponsesConverter()
        let result = converter.convertSSEEvent(
            "data: [DONE]", responseId: "resp-001", model: "gpt-5.5")
        // 无 streamState 时返回空
        #expect(result.isEmpty)
    }

    @Test func 完整流式转换至DONE() {
        var converter = ResponsesConverter()
        // 模拟完整的流式对话
        let events1 = converter.convertSSEEvent(
            "data: {\"id\":\"chatcmpl-1\",\"model\":\"gpt-5.5\",\"choices\":[{\"delta\":{\"content\":\"你好\"},\"index\":0}]}",
            responseId: "resp-001", model: "gpt-5.5")
        #expect(events1.contains { $0.contains("response.created") })
        #expect(events1.contains { $0.contains("output_text.delta") })

        let events2 = converter.convertSSEEvent(
            "data: {\"id\":\"chatcmpl-1\",\"model\":\"gpt-5.5\",\"choices\":[{\"delta\":{\"content\":\"世界\"},\"index\":0}]}",
            responseId: "resp-001", model: "gpt-5.5")
        #expect(events2.allSatisfy { !$0.contains("response.created") })

        let doneEvents = converter.convertSSEEvent(
            "data: [DONE]", responseId: "resp-001", model: "gpt-5.5")
        #expect(doneEvents.contains { $0.contains("response.completed") })
        #expect(doneEvents.contains { $0.contains("output_text.done") })
        #expect(doneEvents.contains { $0.contains("output_item.done") })
    }

    // MARK: - previous_response_id 历史恢复

    @Test func 从历史会话提取消息() throws {
        let prevConv = ConversationRecord(
            responseId: "resp-prev",
            previousResponseId: nil,
            model: "gpt-5.5",
            data: """
                {"id":"resp-prev","model":"gpt-5.5","output":[{"type":"message","role":"assistant","content":[{"type":"output_text","text":"上一条回复"}]}]}
                """
        )

        let responseBody = Data(
            """
            {"model":"gpt-5.5","previous_response_id":"resp-prev","input":"继续"}
            """.utf8)

        let chatBody = try converter.convertRequest(
            responseBody: responseBody,
            upstreamModel: "test-model",
            previousConversations: [prevConv]
        )

        let json = try JSONSerialization.jsonObject(with: chatBody) as! [String: Any]
        let messages = json["messages"] as! [[String: Any]]
        // 应包含历史 assistant 消息 + 当前 user 消息
        #expect(messages.contains { ($0["role"] as? String) == "assistant" })
        #expect(messages.contains { ($0["role"] as? String) == "user" })
    }
}
