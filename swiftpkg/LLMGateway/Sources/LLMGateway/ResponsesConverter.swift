import Foundation

// MARK: - Responses ↔ Chat Completions 请求/响应转换器

public struct ResponsesConverter: Sendable {

    public init() {}

    // MARK: - 流式转换状态

    private var streamState: StreamState?

    private struct StreamState: Sendable {
        var responseID = ""
        var model = ""
        var text = ""
        var reasoningText = ""
        var sequenceNumber = 0
        var messageStarted = false
        var reasoningStarted = false
        var messageItemID: String { "msg_\(responseID)" }
        var reasoningItemID: String { "rs_\(responseID)" }
        mutating func nextSeq() -> Int {
            sequenceNumber += 1
            return sequenceNumber
        }
    }

    // MARK: - 请求转换

    /// 将 Responses API 请求体转换为 Chat Completions API 请求体
    /// - Parameters:
    ///   - responseBody: /v1/responses 的请求 JSON
    ///   - upstreamModel: 上游实际模型名
    ///   - previousConversations: 通过 previous_response_id 查询到的历史会话
    ///   - reasoningEffortMapping: alias 中定义的 reasoningEffort 映射
    /// - Returns: Chat Completions 请求体 Data
    public func convertRequest(
        responseBody: Data,
        upstreamModel: String,
        previousConversations: [ConversationRecord] = [],
        reasoningEffortMapping: [String: String]? = nil
    ) throws -> Data {
        // 已有 messages（客户端直发 chat completions 格式到 /v1/responses）
        if hasExistingMessages(in: responseBody) {
            var raw = try JSONSerialization.jsonObject(with: responseBody) as! [String: Any]
            raw["model"] = upstreamModel
            if let tools = raw["tools"] as? [[String: Any]] {
                raw["tools"] = tools.filter { ($0["type"] as? String) == "function" }
            }
            return try JSONSerialization.data(withJSONObject: raw)
        }

        let req = try JSONDecoder().decode(OpenAIResponsesRequest.self, from: responseBody)
        var chat = OpenAIChatRequest(model: upstreamModel, messages: [])

        var msgs: [ChatMessage] = []

        // instructions → system message
        if let inst = req.instructions, !inst.isEmpty {
            msgs.append(.system(SystemMsg(content: inst)))
        }

        // previous_response_id → 从历史会话中提取消息
        for conv in previousConversations {
            if let d = conv.data.data(using: .utf8),
                let prevResp = try? JSONDecoder().decode(OpenAIResponsesResponse.self, from: d)
            {
                msgs.append(contentsOf: extractMessages(from: prevResp))
            }
        }

        // input
        if let input = req.input {
            msgs.append(contentsOf: convertInput(input))
        }

        chat.messages = msgs
        chat.tools = req.tools
        chat.tool_choice = req.tool_choice
        chat.max_tokens = req.max_output_tokens
        chat.stream = req.stream
        chat.temperature = req.temperature
        chat.top_p = req.top_p
        if let format = req.text?.format { chat.response_format = format }
        if let mapping = reasoningEffortMapping, let effort = req.reasoning?.effort,
            let mapped = mapping[effort]
        {
            chat.reasoning_effort = mapped
        } else if let effort = req.reasoning?.effort {
            chat.reasoning_effort = effort
        }

        return try JSONEncoder().encode(chat)
    }

    private func hasExistingMessages(in body: Data) -> Bool {
        guard let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return false
        }
        return obj["messages"] != nil
    }

    private func convertInput(_ input: ResponseInput) -> [ChatMessage] {
        switch input {
        case .string(let text):
            return [.user(UserMsg(content: text))]
        case .items(let items):
            return items.compactMap { item -> ChatMessage? in
                if item.type == "function_call_output", let cid = item.call_id,
                    let out = item.output
                {
                    return .tool(ToolMsg(content: out, tool_call_id: cid))
                }
                guard let role = item.role, let content = item.content else { return nil }
                return chatMessage(role: role, content: content)
            }
        }
    }

    private func chatMessage(role: String, content: ResponseContent) -> ChatMessage {
        let text: String
        switch content {
        case .string(let s): text = s
        case .blocks(let blocks):
            text = blocks.compactMap { $0.text }.joined(separator: "\n")
        }
        switch role {
        case "system": return .system(SystemMsg(content: text))
        case "assistant": return .assistant(AssistantMsg(content: text))
        case "developer": return .system(SystemMsg(content: text))
        default: return .user(UserMsg(content: text))
        }
    }

    private func extractMessages(from resp: OpenAIResponsesResponse) -> [ChatMessage] {
        guard let output = resp.output else { return [] }
        return output.compactMap { item -> ChatMessage? in
            switch item.type {
            case "message":
                let text =
                    item.content?.compactMap { $0.text }.joined(separator: "\n") ?? ""
                guard !text.isEmpty else { return nil }
                let role = item.role ?? "assistant"
                return role == "assistant"
                    ? .assistant(AssistantMsg(content: text))
                    : .user(UserMsg(content: text))
            case "function_call":
                guard let cid = item.call_id, let name = item.name else { return nil }
                let args = item.arguments ?? "{}"
                return .assistant(
                    AssistantMsg(
                        content: nil,
                        tool_calls: [
                            ToolCall(
                                id: cid,
                                function: FunctionCallArg(name: name, arguments: args)
                            )
                        ]
                    ))
            default:
                return nil
            }
        }
    }

    // MARK: - 响应转换（非流式）

    /// 将 Chat Completions 响应体转换为 Responses API 格式
    public func convertResponse(
        chatResponseBody: Data,
        requestBody: Data,
        responseId: String = ""
    ) throws -> Data {
        let chatResp = try JSONDecoder().decode(OpenAIChatResponse.self, from: chatResponseBody)
        let id =
            chatResp.id.isEmpty
            ? (responseId.isEmpty ? "resp_\(UUID().uuidString)" : responseId)
            : chatResp.id

        var output: [ResponseOutputItem] = []
        let msg = chatResp.choices.first?.message

        if let rc = msg?.reasoning_content, !rc.isEmpty {
            output.append(
                ResponseOutputItem(
                    id: "rs_\(id)", type: "reasoning", status: "completed",
                    content: [ResponseContentBlock(type: "reasoning_text", text: rc)],
                    summary: []
                ))
        }
        if let text = msg?.content, !text.isEmpty {
            output.append(
                ResponseOutputItem(
                    id: "msg_\(id)", type: "message", status: "completed",
                    role: "assistant",
                    content: [
                        ResponseContentBlock(
                            type: "output_text", text: text,
                            annotations: [], logprobs: []
                        )
                    ]
                ))
        }
        if let toolCalls = msg?.tool_calls {
            for tc in toolCalls {
                output.append(
                    ResponseOutputItem(
                        id: "fc_\(tc.id ?? "")", type: "function_call",
                        call_id: tc.id, name: tc.function.name,
                        arguments: tc.function.arguments
                    ))
            }
        }

        var resp = OpenAIResponsesResponse(
            id: id, model: chatResp.model, status: "completed",
            created_at: chatResp.created, output: output,
            output_text: msg?.content
        )
        if let u = chatResp.usage {
            resp.usage = OpenAIResponsesResponse.ResponseUsage(
                input_tokens: u.prompt_tokens,
                output_tokens: u.completion_tokens,
                total_tokens: u.total_tokens
            )
        }
        return try JSONEncoder().encode(resp)
    }

    /// 提取 token 用量
    public func extractUsage(from chatResponseBody: Data) -> (
        promptTokens: Int, completionTokens: Int, totalTokens: Int
    )? {
        guard
            let r = try? JSONDecoder().decode(OpenAIChatResponse.self, from: chatResponseBody),
            let u = r.usage
        else { return nil }
        return (u.prompt_tokens, u.completion_tokens, u.total_tokens)
    }

    // MARK: - SSE 事件转换（流式）

    /// 将 Chat Completions SSE 事件转换为 Responses SSE 事件
    /// 返回多个 SSE 事件字符串
    public mutating func convertSSEEvent(_ sseData: String, responseId: String, model: String)
        -> [String]
    {
        guard sseData.hasPrefix("data: ") else { return [] }

        if sseData == "data: [DONE]" {
            guard var st = streamState else { return [] }
            defer { streamState = nil }
            return finishStream(&st)
        }

        let jsonStr = String(sseData.dropFirst(6))
        guard let data = jsonStr.data(using: .utf8),
            let chunk = try? JSONDecoder().decode(OpenAIChatChunk.self, from: data)
        else { return [] }

        if streamState == nil { streamState = StreamState() }
        var st = streamState!
        defer { streamState = st }

        st.responseID = chunk.id ?? st.responseID
        st.model = chunk.model ?? st.model
        let delta = chunk.choices?.first?.delta
        var events: [String] = []

        if st.sequenceNumber == 0 {
            events.append(
                sseEvent(
                    SSEResponseCreated(
                        response: SSEResponseInfo(
                            id: st.responseID, model: st.model,
                            status: "in_progress", output: []
                        ),
                        sequence_number: st.nextSeq()
                    )))
        }

        if let rc = delta?.reasoning_content, !rc.isEmpty {
            st.reasoningText += rc
            if !st.reasoningStarted {
                st.reasoningStarted = true
                events.append(
                    sseEvent(
                        SSEOutputItemAdded(
                            output_index: 0,
                            item: ResponseOutputItem(
                                id: st.reasoningItemID, type: "reasoning",
                                status: "in_progress", summary: []
                            ),
                            sequence_number: st.nextSeq()
                        )))
                events.append(
                    sseEvent(
                        SSEContentPartAdded(
                            output_index: 0, content_index: 0,
                            item_id: st.reasoningItemID,
                            part: SSEContentPart(type: "reasoning_text", text: ""),
                            sequence_number: st.nextSeq()
                        )))
            }
            events.append(
                sseEvent(
                    SSETextDelta(
                        type: "response.reasoning_text.delta",
                        output_index: 0, content_index: 0,
                        item_id: st.reasoningItemID,
                        delta: rc,
                        sequence_number: st.nextSeq()
                    )))
        }

        if let c = delta?.content, !c.isEmpty {
            st.text += c
            if !st.messageStarted {
                st.messageStarted = true
                let oi = st.reasoningStarted ? 1 : 0
                events.append(
                    sseEvent(
                        SSEOutputItemAdded(
                            output_index: oi,
                            item: ResponseOutputItem(
                                id: st.messageItemID, type: "message",
                                status: "in_progress", role: "assistant",
                                content: []
                            ),
                            sequence_number: st.nextSeq()
                        )))
                events.append(
                    sseEvent(
                        SSEContentPartAdded(
                            output_index: oi, content_index: 0,
                            item_id: st.messageItemID,
                            part: SSEContentPart(
                                type: "output_text", text: "", annotations: []),
                            sequence_number: st.nextSeq()
                        )))
            }
            let oi = st.reasoningStarted ? 1 : 0
            events.append(
                sseEvent(
                    SSETextDelta(
                        type: "response.output_text.delta",
                        output_index: oi, content_index: 0,
                        item_id: st.messageItemID,
                        delta: c,
                        sequence_number: st.nextSeq()
                    )))
        }

        return events
    }

    private func finishStream(_ st: inout StreamState) -> [String] {
        var events: [String] = []

        if st.reasoningStarted {
            events.append(
                sseEvent(
                    SSEReasoningTextDone(
                        output_index: 0, content_index: 0,
                        item_id: st.reasoningItemID, text: st.reasoningText,
                        sequence_number: st.nextSeq()
                    )))
            events.append(
                sseEvent(
                    SSEOutputItemDone(
                        output_index: 0,
                        item: ResponseOutputItem(
                            id: st.reasoningItemID, type: "reasoning",
                            status: "completed",
                            content: [
                                ResponseContentBlock(
                                    type: "reasoning_text", text: st.reasoningText)
                            ],
                            summary: []
                        ),
                        sequence_number: st.nextSeq()
                    )))
        }

        if st.messageStarted {
            let oi = st.reasoningStarted ? 1 : 0
            events.append(
                sseEvent(
                    SSEOutputTextDone(
                        output_index: oi, content_index: 0,
                        item_id: st.messageItemID, text: st.text,
                        sequence_number: st.nextSeq()
                    )))
            events.append(
                sseEvent(
                    SSEOutputItemDone(
                        output_index: oi,
                        item: ResponseOutputItem(
                            id: st.messageItemID, type: "message",
                            status: "completed", role: "assistant",
                            content: [
                                ResponseContentBlock(
                                    type: "output_text", text: st.text,
                                    annotations: [], logprobs: []
                                )
                            ]
                        ),
                        sequence_number: st.nextSeq()
                    )))
        }

        var outputItems: [ResponseOutputItem] = []
        if st.reasoningStarted {
            outputItems.append(
                ResponseOutputItem(
                    id: st.reasoningItemID, type: "reasoning", status: "completed",
                    content: [
                        ResponseContentBlock(type: "reasoning_text", text: st.reasoningText)
                    ],
                    summary: []
                ))
        }
        if st.messageStarted {
            outputItems.append(
                ResponseOutputItem(
                    id: st.messageItemID, type: "message", status: "completed",
                    role: "assistant",
                    content: [
                        ResponseContentBlock(
                            type: "output_text", text: st.text,
                            annotations: [], logprobs: []
                        )
                    ]
                ))
        }

        events.append(
            sseEvent(
                SSEResponseCompleted(
                    response: SSEResponseInfo(
                        id: st.responseID, model: st.model, status: "completed",
                        output: outputItems, output_text: st.text
                    ),
                    sequence_number: st.nextSeq()
                )))

        return events
    }

    private func sseEvent<T: Codable>(_ event: T) -> String {
        guard let d = try? JSONEncoder().encode(event),
            let s = String(data: d, encoding: .utf8)
        else { return "" }
        return "data: \(s)"
    }
}

// MARK: - SSE Event Codable Types

private struct SSEResponseCreated: Codable {
    var type = "response.created"
    var response: SSEResponseInfo
    var sequence_number: Int
}

private struct SSEResponseInfo: Codable {
    var id: String
    var object = "response"
    var model: String
    var status: String
    var output: [ResponseOutputItem]
    var output_text: String?
}

private struct SSEOutputItemAdded: Codable {
    var type = "response.output_item.added"
    var output_index: Int
    var item: ResponseOutputItem
    var sequence_number: Int
}

private struct SSEContentPartAdded: Codable {
    var type = "response.content_part.added"
    var output_index: Int
    var content_index: Int
    var item_id: String
    var part: SSEContentPart
    var sequence_number: Int
}

private struct SSEContentPart: Codable {
    var type: String
    var text: String
    var annotations: [String]?
}

private struct SSETextDelta: Codable {
    var type: String
    var output_index: Int
    var content_index: Int
    var item_id: String
    var delta: String
    var sequence_number: Int
}

private struct SSEReasoningTextDone: Codable {
    var type = "response.reasoning_text.done"
    var output_index: Int
    var content_index: Int
    var item_id: String
    var text: String
    var sequence_number: Int
}

private struct SSEOutputTextDone: Codable {
    var type = "response.output_text.done"
    var output_index: Int
    var content_index: Int
    var item_id: String
    var text: String
    var logprobs: [String] = []
    var sequence_number: Int
}

private struct SSEOutputItemDone: Codable {
    var type = "response.output_item.done"
    var output_index: Int
    var item: ResponseOutputItem
    var sequence_number: Int
}

private struct SSEResponseCompleted: Codable {
    var type = "response.completed"
    var response: SSEResponseInfo
    var sequence_number: Int
}

// MARK: - 转换错误

public enum ConversionError: LocalizedError, Sendable {
    case invalidRequestBody
    case invalidResponseBody
    case historyNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRequestBody:
            return "无效的请求体：无法解析 Responses API 格式"
        case .invalidResponseBody:
            return "无效的响应体：无法解析 Chat Completions 格式"
        case .historyNotFound(let responseId):
            return "未找到历史会话: \(responseId)"
        }
    }
}
