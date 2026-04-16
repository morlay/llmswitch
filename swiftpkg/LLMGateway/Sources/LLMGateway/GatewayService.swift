import Foundation

// MARK: - 网关服务

public actor GatewayService {
    private let config: GatewayConfig
    private var state: GatewayRuntimeState
    private let logger: GatewayLogger
    private let usageStore: GatewayUsageStore
    private var converter: ResponsesConverter
    private let session: URLSession

    public init(
        config: GatewayConfig,
        state: GatewayRuntimeState,
        logger: GatewayLogger,
        usageStore: GatewayUsageStore,
        session: URLSession = .shared
    ) {
        self.config = config
        self.state = state
        self.logger = logger
        self.usageStore = usageStore
        self.converter = ResponsesConverter()
        self.session = session
    }

    public func handleOutput(_ request: HTTPRequest, writer: any HTTPResponseWriter) async {
        let startTime = ContinuousClock.now

        do {
            try await handleRequest(request, writer: writer, startTime: startTime)
        } catch is AuthError {
            try? await sendError(
                statusCode: 401, message: "未授权：缺少或无效的 API Key", writer: writer)
        } catch {
            await logError(request: request, error: error, startTime: startTime)
            try? await sendError(
                statusCode: 500, message: error.localizedDescription, writer: writer)
        }
    }

    // MARK: - 路由分发

    private func handleRequest(
        _ request: HTTPRequest,
        writer: any HTTPResponseWriter,
        startTime: ContinuousClock.Instant
    ) async throws {
        let ua = request.headers.first(where: {
            $0.key.caseInsensitiveCompare("user-agent") == .orderedSame
        })?.value
            .components(separatedBy: "/").first
            .map { $0.trimmingCharacters(in: .whitespaces) }

        switch (request.method, request.path) {
        case ("GET", "/v1/models"):
            try await handleModelsList(writer: writer, startTime: startTime, userAgent: ua)

        case ("POST", "/v1/responses"):
            try await requireAuth(request)
            try await handleProxy(
                request: request, writer: writer, startTime: startTime, endpoint: "/v1/responses",
                userAgent: ua)

        case ("POST", "/v1/chat/completions"):
            try await requireAuth(request)
            try await handleProxy(
                request: request, writer: writer, startTime: startTime,
                endpoint: "/v1/chat/completions", userAgent: ua)

        case ("POST", _) where request.path.hasPrefix("/v1/"):
            try await requireAuth(request)
            try await handleProxy(
                request: request, writer: writer, startTime: startTime, endpoint: request.path,
                userAgent: ua)

        default:
            try await sendError(
                statusCode: 405, message: "不支持的方法: \(request.method) \(request.path)",
                writer: writer)
        }
    }

    // MARK: - /v1/models

    private func handleModelsList(
        writer: any HTTPResponseWriter, startTime: ContinuousClock.Instant,
        userAgent: String? = nil
    ) async throws {
        let modelIDs = state.allExposedModels(config: config)
        let models = modelIDs.map { modelName -> [String: Any] in
            ["id": modelName, "object": "model", "created": 0, "owned_by": "llmswitch"]
        }

        let body = try JSONSerialization.data(withJSONObject: ["object": "list", "data": models])
        try await writer.send(
            statusCode: 200, headers: ["Content-Type": "application/json"], body: body)

        let elapsed = latencyMs(from: startTime)
        await logger.log(
            AccessLogEntry(
                method: "GET", path: "/v1/models", statusCode: 200, latencyMs: elapsed,
                userAgent: userAgent))
    }

    // MARK: - 代理转发

    private func handleProxy(
        request: HTTPRequest,
        writer: any HTTPResponseWriter,
        startTime: ContinuousClock.Instant,
        endpoint: String,
        userAgent: String? = nil
    ) async throws {
        guard let publicModel = request.extractModelFromBody() else {
            try await sendError(statusCode: 400, message: "请求体中缺少 model 字段", writer: writer)
            return
        }

        guard let binding = state.binding(for: publicModel) else {
            try await sendError(
                statusCode: 404, message: "模型 '\(publicModel)' 未启用或不存在", writer: writer)
            return
        }

        guard let provider = config.provider(named: binding.provider) else {
            try await sendError(
                statusCode: 500, message: "Provider '\(binding.provider)' 配置缺失", writer: writer)
            return
        }

        let upstreamEndpoint: String
        let upstreamBody: Data

        if endpoint == "/v1/responses" && !provider.type.supportsResponses {
            await logger.info("转换 responses → chat/completions")
            if let origBody = String(data: request.body, encoding: .utf8) {
                await logger.info("原始请求: \(origBody)")
            }
            upstreamEndpoint = "/v1/chat/completions"
            let reasoningMapping = provider.aliases?[publicModel]?.reasoningEfforts

            var previousConvs: [ConversationRecord] = []
            if let body = request.bodyJSON(), let prevId = body["previous_response_id"] as? String {
                if let conv = try? await usageStore.findConversation(responseId: prevId) {
                    previousConvs.append(conv)
                }
                if let subsequent = try? await usageStore.findConversationsByPrevious(
                    responseId: prevId)
                {
                    previousConvs.append(contentsOf: subsequent)
                }
            }

            upstreamBody = try converter.convertRequest(
                responseBody: request.body,
                upstreamModel: binding.upstreamModel,
                previousConversations: previousConvs,
                reasoningEffortMapping: reasoningMapping
            )
        } else {
            upstreamEndpoint = endpoint
            upstreamBody = try replaceModelInBody(request.body, with: binding.upstreamModel)
        }

        guard
            let upstreamURL = provider.buildUpstreamURL(
                path: upstreamEndpoint, query: request.query)
        else {
            try await sendError(statusCode: 500, message: "无法构建上游 URL", writer: writer)
            return
        }

        var upstreamRequest = URLRequest(url: upstreamURL)
        upstreamRequest.httpMethod = request.method
        upstreamRequest.httpBody = upstreamBody
        applyForwardedHeaders(from: request, to: &upstreamRequest, apiKey: provider.resolvedAPIKey)

        if let reqBodyStr = String(data: upstreamBody, encoding: .utf8) {
            let headLine = "\(upstreamRequest.httpMethod ?? "POST") \(upstreamURL.absoluteString)"
            let headerLines =
                upstreamRequest.allHTTPHeaderFields?.map { k, v in
                    let masked =
                        ["authorization", "x-api-key"].contains(k.lowercased()) ? "***" : v
                    return "\(k): \(masked)"
                }.joined(separator: "\n") ?? ""
            await logger.logRequest("\(headLine)\n\(headerLines)\n\n\(reqBodyStr)")
        }

        await logger.info(
            "转发 → \(provider.name) \(upstreamEndpoint) model=\(binding.upstreamModel)")

        let isStream = request.bodyJSON()?["stream"] as? Bool ?? false
        let acceptHeader = request.headers["accept"] ?? ""
        let needsConvert = endpoint == "/v1/responses" && !provider.type.supportsResponses

        if isStream || acceptHeader.contains("text/event-stream") {
            try await proxyStream(
                upstreamRequest: upstreamRequest, writer: writer,
                publicModel: publicModel, provider: provider, endpoint: endpoint,
                binding: binding, startTime: startTime, originalBody: request.body,
                needsConvert: needsConvert, userAgent: userAgent
            )
        } else {
            try await proxyNonStream(
                upstreamRequest: upstreamRequest, writer: writer,
                publicModel: publicModel, provider: provider, endpoint: endpoint,
                binding: binding, startTime: startTime, originalBody: request.body,
                needsConvert: needsConvert, userAgent: userAgent
            )
        }
    }

    // MARK: - 非流式代理

    private func proxyNonStream(
        upstreamRequest: URLRequest, writer: any HTTPResponseWriter,
        publicModel: String, provider: ProviderConfig, endpoint: String,
        binding: ModelBinding, startTime: ContinuousClock.Instant,
        originalBody: Data, needsConvert: Bool,
        userAgent: String? = nil
    ) async throws {
        let (data, response) = try await session.data(for: upstreamRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        let respHeadLine =
            "HTTP \(httpResponse.statusCode) \(reasonPhrase(for: httpResponse.statusCode))"
        let respHeaderLines = httpResponse.allHeaderFields.map { "\($0.key): \($0.value)" }.joined(
            separator: "\n")
        await logger.logResponseHead("\(respHeadLine)\n\(respHeaderLines)")

        if let bodyStr = String(data: data, encoding: .utf8), !bodyStr.isEmpty {
            await logger.info("上游响应体(\(httpResponse.statusCode)): \(bodyStr)")
        }

        let elapsed = latencyMs(from: startTime)
        var responseBody = data
        var promptTokens = 0
        var completionTokens = 0
        var totalTokens = 0

        if needsConvert && httpResponse.statusCode == 200 {
            let responseId = "resp_\(UUID().uuidString)"
            responseBody = try converter.convertResponse(
                chatResponseBody: data, requestBody: originalBody, responseId: responseId)

            if let usage = converter.extractUsage(from: data) {
                promptTokens = usage.promptTokens
                completionTokens = usage.completionTokens
                totalTokens = usage.totalTokens
            }

            if let respStr = String(data: responseBody, encoding: .utf8) {
                let prevId = originalBody.bodyJSON()?["previous_response_id"] as? String
                try? await usageStore.saveConversation(
                    ConversationRecord(
                        responseId: responseId, previousResponseId: prevId, model: publicModel,
                        data: respStr
                    ))
            }
        } else if httpResponse.statusCode == 200 {
            if let respJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let usage = respJSON["usage"] as? [String: Any]
            {
                promptTokens = usage["input_tokens"] as? Int ?? usage["prompt_tokens"] as? Int ?? 0
                completionTokens =
                    usage["output_tokens"] as? Int ?? usage["completion_tokens"] as? Int ?? 0
                totalTokens = usage["total_tokens"] as? Int ?? 0
            }

            if endpoint == "/v1/responses",
                let respJSON = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let responseId = respJSON["id"] as? String,
                let respStr = String(data: data, encoding: .utf8)
            {
                let prevId = originalBody.bodyJSON()?["previous_response_id"] as? String
                try? await usageStore.saveConversation(
                    ConversationRecord(
                        responseId: responseId, previousResponseId: prevId, model: publicModel,
                        data: respStr
                    ))
            }
        }

        try? await usageStore.recordUsage(
            TokenUsageRecord(
                model: publicModel, provider: provider.name, endpoint: endpoint,
                statusCode: httpResponse.statusCode, latencyMs: elapsed,
                promptTokens: promptTokens, completionTokens: completionTokens,
                totalTokens: totalTokens
            ))

        var responseHeaders = forwardedResponseHeaders(from: httpResponse)
        responseHeaders.removeValue(forKey: "Content-Encoding")
        // alias 映射时替换响应中的 model 为公开模型名
        if binding.upstreamModel != publicModel,
            var respJSON = try? JSONSerialization.jsonObject(with: responseBody) as? [String: Any]
        {
            respJSON["model"] = publicModel
            responseBody = (try? JSONSerialization.data(withJSONObject: respJSON)) ?? responseBody
        }
        responseHeaders["Content-Type"] = "application/json"
        try await writer.send(
            statusCode: httpResponse.statusCode, headers: responseHeaders, body: responseBody)

        await logger.log(
            AccessLogEntry(
                method: "POST", path: endpoint, statusCode: httpResponse.statusCode,
                latencyMs: elapsed, model: publicModel,
                target: "\(provider.name)/\(binding.upstreamModel)",
                userAgent: userAgent
            ))
    }

    // MARK: - 流式代理

    private func proxyStream(
        upstreamRequest: URLRequest, writer: any HTTPResponseWriter,
        publicModel: String, provider: ProviderConfig, endpoint: String,
        binding: ModelBinding, startTime: ContinuousClock.Instant,
        originalBody: Data, needsConvert: Bool,
        userAgent: String? = nil
    ) async throws {
        let (bytes, response) = try await session.bytes(for: upstreamRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        let respHeadLine =
            "HTTP \(httpResponse.statusCode) \(reasonPhrase(for: httpResponse.statusCode))"
        let respHeaderLines = httpResponse.allHeaderFields.map { "\($0.key): \($0.value)" }.joined(
            separator: "\n")
        await logger.logResponseHead("\(respHeadLine)\n\(respHeaderLines)")

        var responseHeaders = forwardedResponseHeaders(from: httpResponse)
        responseHeaders.removeValue(forKey: "Content-Encoding")
        if needsConvert {
            responseHeaders["Content-Type"] = "text/event-stream"
        }

        try await writer.startChunkedResponse(
            statusCode: httpResponse.statusCode, headers: responseHeaders)

        let responseId = "resp_\(UUID().uuidString)"
        var accumulatedData = Data()

        if needsConvert {
            for try await line in bytes.lines {
                if line.hasPrefix("data: ") {
                    for converted in converter.convertSSEEvent(
                        line, responseId: responseId, model: publicModel)
                    {
                        try await writer.sendChunk(Data("\(converted)\n\n".utf8))
                    }
                }
                accumulatedData.append(Data("\(line)\n".utf8))
            }
            try await writer.sendChunk(Data("data: [DONE]\n\n".utf8))
        } else {
            for try await byte in bytes {
                accumulatedData.append(byte)
                if accumulatedData.count >= 4096 {
                    try await writer.sendChunk(accumulatedData)
                    accumulatedData.removeAll(keepingCapacity: true)
                }
            }
            if !accumulatedData.isEmpty {
                try await writer.sendChunk(accumulatedData)
            }
        }

        try await writer.finishChunkedResponse()

        let elapsed = latencyMs(from: startTime)
        try? await usageStore.recordUsage(
            TokenUsageRecord(
                model: publicModel, provider: provider.name, endpoint: endpoint,
                statusCode: httpResponse.statusCode, latencyMs: elapsed, stream: true
            ))

        await logger.log(
            AccessLogEntry(
                method: "POST", path: endpoint, statusCode: httpResponse.statusCode,
                latencyMs: elapsed, model: publicModel,
                target: "\(provider.name)/\(binding.upstreamModel)",
                userAgent: userAgent
            ))
    }

    // MARK: - 鉴权

    private func requireAuth(_ request: HTTPRequest) async throws {
        let authorization = request.headers.first(where: {
            $0.key.caseInsensitiveCompare("authorization") == .orderedSame
        })?.value
        guard let auth = authorization?.trimmingCharacters(in: .whitespacesAndNewlines),
            !auth.isEmpty
        else {
            throw AuthError.unauthorized
        }
        let lowercased = auth.lowercased()
        guard lowercased.hasPrefix("bearer ") else {
            throw AuthError.unauthorized
        }
        let token = String(auth.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard token == config.auth.apiKey else {
            throw AuthError.unauthorized
        }
    }

    // MARK: - 动态切换

    public func switchModelBinding(model: String, to provider: String, upstreamModel: String) {
        state.switchBinding(model: model, to: provider, upstreamModel: upstreamModel)
    }

    public var currentBindings: [String: ModelBinding] {
        state.activeBindings
    }

    // MARK: - 辅助

    private func replaceModelInBody(_ body: Data, with model: String) throws -> Data {
        guard var json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return body
        }
        json["model"] = model
        return try JSONSerialization.data(withJSONObject: json)
    }

    private func applyForwardedHeaders(
        from request: HTTPRequest, to upstreamRequest: inout URLRequest, apiKey: String
    ) {
        let blockedHeaders: Set<String> = [
            "authorization", "connection", "content-length", "host", "transfer-encoding",
        ]
        for headerName in request.headers.keys.sorted() {
            guard !blockedHeaders.contains(headerName), let value = request.headers[headerName]
            else { continue }
            upstreamRequest.setValue(value, forHTTPHeaderField: headerName)
        }
        upstreamRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        upstreamRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    private func forwardedResponseHeaders(from response: HTTPURLResponse) -> [String: String] {
        var headers: [String: String] = [:]
        let blockedHeaders: Set<String> = ["connection", "content-length", "transfer-encoding"]
        for (rawName, rawValue) in response.allHeaderFields {
            guard let name = rawName as? String, let value = rawValue as? String else { continue }
            guard !blockedHeaders.contains(name.lowercased()) else { continue }
            headers[name] = value
        }
        return headers
    }

    private func sendError(statusCode: Int, message: String, writer: any HTTPResponseWriter)
        async throws
    {
        let body = Data(
            """
            {"error":{"message":"\(escapeJSON(message))","type":"invalid_request_error"}}
            """.utf8)
        try await writer.send(
            statusCode: statusCode, headers: ["Content-Type": "application/json"], body: body)
    }

    private func logError(request: HTTPRequest, error: Error, startTime: ContinuousClock.Instant)
        async
    {
        let ua = request.headers.first(where: { $0.key.caseInsensitiveCompare("user-agent") == .orderedSame })?.value
            .components(separatedBy: "/").first
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let elapsed = latencyMs(from: startTime)
        await logger.log(
            AccessLogEntry(
                method: request.method, path: request.path, statusCode: 500,
                latencyMs: elapsed, errorMessage: error.localizedDescription,
                userAgent: ua
            ))
    }
}

private func latencyMs(from startTime: ContinuousClock.Instant) -> Int64 {
    let duration = startTime.duration(to: ContinuousClock.now)
    return Int64(duration.components.seconds * 1000)
        + Int64(duration.components.attoseconds / 1_000_000_000_000_000)
}

private enum AuthError: LocalizedError {
    case unauthorized
    var errorDescription: String? { "未授权：缺少或无效的 API Key" }
}

extension Data {
    func bodyJSON() -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: self)) as? [String: Any]
    }
}
