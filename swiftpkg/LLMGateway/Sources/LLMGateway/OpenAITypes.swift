import Foundation

// MARK: - Chat Completions Request

struct OpenAIChatRequest: Codable {
    var model: String
    var messages: [ChatMessage]
    var stream: Bool?
    var max_tokens: Int?
    var temperature: Double?
    var top_p: Double?
    var tools: [ChatTool]?
    var tool_choice: ToolChoice?
    var response_format: ResponseFormat?
    var reasoning_effort: String?
    var stop: StopValue?
}

enum ChatMessage: Codable {
    case system(SystemMsg)
    case user(UserMsg)
    case assistant(AssistantMsg)
    case tool(ToolMsg)

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .role) {
        case "system": self = .system(try SystemMsg(from: decoder))
        case "user": self = .user(try UserMsg(from: decoder))
        case "assistant": self = .assistant(try AssistantMsg(from: decoder))
        case "tool": self = .tool(try ToolMsg(from: decoder))
        case let r:
            throw DecodingError.dataCorruptedError(
                forKey: .role, in: c, debugDescription: "unknown role: \(r)")
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .system(let m): try m.encode(to: encoder)
        case .user(let m): try m.encode(to: encoder)
        case .assistant(let m): try m.encode(to: encoder)
        case .tool(let m): try m.encode(to: encoder)
        }
    }

    enum CodingKeys: String, CodingKey { case role }
}

struct SystemMsg: Codable {
    var role = "system"
    var content: String
    var name: String?
}

struct UserMsg: Codable {
    var role = "user"
    var content: String
    var name: String?
}

struct AssistantMsg: Codable {
    var role = "assistant"
    var content: String?
    var name: String?
    var tool_calls: [ToolCall]?
    var reasoning_content: String?
}

struct ToolMsg: Codable {
    var role = "tool"
    var content: String
    var tool_call_id: String
}

struct FailableTool: Codable {
    var tool: ChatTool?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        tool = try? c.decode(ChatTool.self)
    }
}

struct ChatTool: Codable {
    var type = "function"
    var function: ChatFunctionDef
}

struct ChatFunctionDef: Codable {
    var name: String
    var description: String?
    var parameters: JSONSchemaProperty?
    var strict: Bool?
}

final class JSONSchemaProperty: Codable {
    var type: String?
    var description: String?
    var items: JSONSchemaProperty?
    var properties: [String: JSONSchemaProperty]?
    var required: [String]?
    var additionalProperties: JSONValue?
    var `enum`: [String]?

    enum CodingKeys: String, CodingKey {
        case type, description, items, properties, required, additionalProperties
        case `enum` = "enum"
    }
}

enum JSONValue: Codable, Equatable {
    case bool(Bool)
    case string(String)
    case int(Int)
    case double(Double)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let i = try? c.decode(Int.self) {
            self = .int(i)
        } else if let d = try? c.decode(Double.self) {
            self = .double(d)
        } else if let a = try? c.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            self = .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .bool(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .int(let v): try c.encode(v)
        case .double(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
}

enum ToolChoice: Codable {
    case none
    case auto
    case required
    case function(name: String)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            switch s {
            case "none": self = .none
            case "auto": self = .auto
            case "required": self = .required
            default: self = .function(name: s)
            }
        } else {
            let d = try c.decode([String: [String: String]].self)
            self = .function(name: d["function"]?["name"] ?? "")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .none: try c.encode("none")
        case .auto: try c.encode("auto")
        case .required: try c.encode("required")
        case .function(let n): try c.encode(FunctionChoice(name: n))
        }
    }

    private struct FunctionChoice: Codable {
        var type = "function"
        var function: FunctionName
        struct FunctionName: Codable { var name: String }
        init(name: String) { self.function = FunctionName(name: name) }
    }
}

struct ResponseFormat: Codable {
    var type: String
}

enum StopValue: Codable {
    case single(String)
    case list([String])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            self = .single(s)
        } else {
            self = .list(try c.decode([String].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .single(let s): try c.encode(s)
        case .list(let l): try c.encode(l)
        }
    }
}

struct ToolCall: Codable {
    var id: String?
    var type = "function"
    var function: FunctionCallArg
}

struct FunctionCallArg: Codable {
    var name: String
    var arguments: String
}

// MARK: - Chat Completions Response

struct OpenAIChatResponse: Codable {
    var id: String
    var object = "chat.completion"
    var created: Int
    var model: String
    var choices: [ChatChoice]
    var usage: ChatUsage?
    var system_fingerprint: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        object = try c.decodeIfPresent(String.self, forKey: .object) ?? "chat.completion"
        created = try c.decode(Int.self, forKey: .created)
        model = try c.decode(String.self, forKey: .model)
        choices = try c.decode([ChatChoice].self, forKey: .choices)
        usage = try c.decodeIfPresent(ChatUsage.self, forKey: .usage)
        system_fingerprint = try c.decodeIfPresent(String.self, forKey: .system_fingerprint)
    }

    enum CodingKeys: String, CodingKey {
        case id, object, created, model, choices, usage, system_fingerprint
    }

    struct ChatChoice: Codable {
        var index: Int
        var message: AssistantMsg
        var finish_reason: String?
        var logprobs: Logprobs?
    }

    struct ChatUsage: Codable {
        var prompt_tokens: Int
        var completion_tokens: Int
        var total_tokens: Int
        var prompt_cache_hit_tokens: Int?
        var prompt_cache_miss_tokens: Int?
        var completion_tokens_details: CompletionTokensDetails?
    }

    struct CompletionTokensDetails: Codable {
        var reasoning_tokens: Int?
    }

    struct Logprobs: Codable {
        var content: [TokenLogprob]?
    }

    struct TokenLogprob: Codable {
        var token: String
        var logprob: Double
        var bytes: [Int]?
        var top_logprobs: [TopLogprob]?
    }

    struct TopLogprob: Codable {
        var token: String
        var logprob: Double
        var bytes: [Int]?
    }
}

// MARK: - Chat Completions Chunk (Streaming)

struct OpenAIChatChunk: Codable {
    var id: String?
    var object = "chat.completion.chunk"
    var created: Int?
    var model: String?
    var choices: [ChunkChoice]?
    var usage: OpenAIChatResponse.ChatUsage?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        object = try c.decodeIfPresent(String.self, forKey: .object) ?? "chat.completion.chunk"
        created = try c.decodeIfPresent(Int.self, forKey: .created)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        choices = try c.decodeIfPresent([ChunkChoice].self, forKey: .choices)
        usage = try c.decodeIfPresent(OpenAIChatResponse.ChatUsage.self, forKey: .usage)
    }

    enum CodingKeys: String, CodingKey {
        case id, object, created, model, choices, usage
    }

    struct ChunkChoice: Codable {
        var index: Int
        var delta: ChunkDelta
        var finish_reason: String?
    }

    struct ChunkDelta: Codable {
        var role: String?
        var content: String?
        var reasoning_content: String?
        var tool_calls: [ToolCall]?
    }
}

// MARK: - Responses API Request

struct OpenAIResponsesRequest: Codable {
    var model: String
    var input: ResponseInput?
    var instructions: String?
    var tools: [ChatTool]?
    var tool_choice: ToolChoice?
    var stream: Bool?
    var max_output_tokens: Int?
    var temperature: Double?
    var top_p: Double?
    var previous_response_id: String?
    var text: TextFormat?
    var reasoning: Reasoning?

    struct TextFormat: Codable { var format: ResponseFormat? }
    struct Reasoning: Codable { var effort: String? }

    enum CodingKeys: String, CodingKey {
        case model, input, instructions, tools, tool_choice, stream
        case max_output_tokens, temperature, top_p, previous_response_id, text, reasoning
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model = try c.decode(String.self, forKey: .model)
        input = try c.decodeIfPresent(ResponseInput.self, forKey: .input)
        instructions = try c.decodeIfPresent(String.self, forKey: .instructions)
        tools = (try? c.decodeIfPresent([FailableTool].self, forKey: .tools))?.compactMap { $0.tool }
        tool_choice = try c.decodeIfPresent(ToolChoice.self, forKey: .tool_choice)
        stream = try c.decodeIfPresent(Bool.self, forKey: .stream)
        max_output_tokens = try c.decodeIfPresent(Int.self, forKey: .max_output_tokens)
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature)
        top_p = try c.decodeIfPresent(Double.self, forKey: .top_p)
        previous_response_id = try c.decodeIfPresent(String.self, forKey: .previous_response_id)
        text = try c.decodeIfPresent(TextFormat.self, forKey: .text)
        reasoning = try c.decodeIfPresent(Reasoning.self, forKey: .reasoning)
    }
}

enum ResponseInput: Codable {
    case string(String)
    case items([ResponseInputItem])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            self = .string(s)
        } else {
            self = .items(try c.decode([ResponseInputItem].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .items(let i): try c.encode(i)
        }
    }
}

struct ResponseInputItem: Codable {
    var type: String?
    var role: String?
    var content: ResponseContent?
    var call_id: String?
    var output: String?
}

enum ResponseContent: Codable {
    case string(String)
    case blocks([ResponseContentBlock])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            self = .string(s)
        } else {
            self = .blocks(try c.decode([ResponseContentBlock].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .blocks(let b): try c.encode(b)
        }
    }
}

struct ResponseContentBlock: Codable {
    var type: String?
    var text: String?
    var image_url: String?
    var annotations: [String]?
    var logprobs: [String]?
}

// MARK: - Responses API Response

struct OpenAIResponsesResponse: Codable {
    var id: String
    var object = "response"
    var model: String
    var status: String?
    var created_at: Int?
    var output: [ResponseOutputItem]?
    var output_text: String?
    var usage: ResponseUsage?

    init(
        id: String,
        object: String = "response",
        model: String,
        status: String? = nil,
        created_at: Int? = nil,
        output: [ResponseOutputItem]? = nil,
        output_text: String? = nil,
        usage: ResponseUsage? = nil
    ) {
        self.id = id
        self.object = object
        self.model = model
        self.status = status
        self.created_at = created_at
        self.output = output
        self.output_text = output_text
        self.usage = usage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        object = try c.decodeIfPresent(String.self, forKey: .object) ?? "response"
        model = try c.decode(String.self, forKey: .model)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        created_at = try c.decodeIfPresent(Int.self, forKey: .created_at)
        output = try c.decodeIfPresent([ResponseOutputItem].self, forKey: .output)
        output_text = try c.decodeIfPresent(String.self, forKey: .output_text)
        usage = try c.decodeIfPresent(ResponseUsage.self, forKey: .usage)
    }

    enum CodingKeys: String, CodingKey {
        case id, object, model, status, created_at, output, output_text, usage
    }

    struct ResponseUsage: Codable {
        var input_tokens: Int?
        var output_tokens: Int?
        var total_tokens: Int?
    }
}

struct ResponseOutputItem: Codable {
    var id: String?
    var type: String
    var status: String?
    var role: String?
    var content: [ResponseContentBlock]?
    var call_id: String?
    var name: String?
    var arguments: String?
    var summary: [String]?
}
