import Foundation

private struct OpenAIModelListResponse: Encodable {
    let object = "list"
    let data: [OpenAIModelEntry]
}

private struct OpenAIModelEntry: Encodable {
    let id: String
    let object = "model"
    let created = 0
    let ownedBy: String

    enum CodingKeys: String, CodingKey {
        case id
        case object
        case created
        case ownedBy = "owned_by"
    }
}

public actor ProxyService {
    private let config: AppConfig
    private var state: AppState
    private let cacheStore: CacheStore
    private let providerClient: ProviderClient
    private let session: URLSession
    private var snapshots: [String: ProviderCacheSnapshot]

    public init(
        config: AppConfig,
        state: AppState,
        cacheStore: CacheStore,
        providerClient: ProviderClient,
        session: URLSession,
        snapshots: [String: ProviderCacheSnapshot] = [:]
    ) {
        self.config = config
        self.state = state
        self.cacheStore = cacheStore
        self.providerClient = providerClient
        self.session = session
        self.snapshots = snapshots
    }

    public func refreshModelCatalogs() async {
        await withTaskGroup(of: (String, Result<[ProviderModel], Error>).self) { group in
            for providerName in config.providers.keys.sorted() {
                guard let provider = config.providers[providerName], provider.enabled else {
                    continue
                }

                group.addTask {
                    do {
                        return (providerName, .success(try await self.providerClient.fetchModels(for: provider)))
                    } catch {
                        return (providerName, .failure(error))
                    }
                }
            }

            for await (providerName, result) in group {
                switch result {
                case let .success(models):
                    let meta = ProviderCacheMeta(
                        providerName: providerName,
                        fetchedAt: Date(),
                        wasSuccessful: true,
                        errorMessage: nil
                    )
                    let snapshot = ProviderCacheSnapshot(meta: meta, models: models)
                    snapshots[providerName] = snapshot
                    do {
                        try cacheStore.saveSuccess(providerName: providerName, models: models, fetchedAt: meta.fetchedAt)
                    } catch {
                        fputs("failed to save cache for \(providerName): \(error)\n", stderr)
                    }
                case let .failure(error):
                    do {
                        try cacheStore.saveFailure(
                            providerName: providerName,
                            errorMessage: error.localizedDescription,
                            fetchedAt: Date()
                        )
                        if let existing = try cacheStore.load(providerName: providerName) {
                            snapshots[providerName] = existing
                        }
                    } catch {
                        fputs("failed to save failure cache for \(providerName): \(error)\n", stderr)
                    }
                }
            }
        }
    }

    public func handle(_ request: HTTPRequest, writer: HTTPConnectionWriter) async {
        do {
            if let response = try await response(for: request) {
                try await writer.send(
                    statusCode: response.statusCode,
                    headers: response.headers,
                    body: response.body
                )
                return
            }
        } catch {
            try? await sendError(statusCode: 500, message: error.localizedDescription, writer: writer)
        }
    }

    func response(for request: HTTPRequest) async throws -> HTTPResponsePayload? {
        guard isAuthorized(request: request) else {
            return HTTPResponsePayload(
                statusCode: 401,
                headers: [
                    "Content-Type": "application/json",
                    "WWW-Authenticate": "Bearer",
                ],
                body: Data("""
                {"error":{"message":"invalid api key","type":"authentication_error"}}
                """.utf8)
            )
        }

        switch (request.method, request.path) {
        case ("GET", "/v1/models"):
            return try modelsListResponse()
        case ("POST", _):
            guard request.path.hasPrefix("/v1/") else {
                return errorResponse(statusCode: 404, message: "unknown path")
            }
            return nil
        default:
            return errorResponse(statusCode: 405, message: "method not allowed")
        }
    }

    private func modelsListResponse() throws -> HTTPResponsePayload {
        let registry = ModelRegistry(config: config, state: state, snapshots: snapshots)
        let payload = OpenAIModelListResponse(
            data: registry.listModels().map { model in
                OpenAIModelEntry(id: model.publicName, ownedBy: model.providerDisplayName)
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return HTTPResponsePayload(
            statusCode: 200,
            headers: ["Content-Type": "application/json"],
            body: try encoder.encode(payload)
        )
    }

    private func proxyUpstream(request: HTTPRequest, writer: HTTPConnectionWriter) async throws {
        guard let requestedModel = extractModelName(from: request.body) else {
            try await sendError(statusCode: 400, message: "request body is missing model", writer: writer)
            return
        }

        let registry = ModelRegistry(config: config, state: state, snapshots: snapshots)
        guard let resolvedModel = registry.resolve(modelName: requestedModel) else {
            try await sendError(statusCode: 404, message: "model is not enabled", writer: writer)
            return
        }

        guard let provider = config.providers[resolvedModel.providerName] else {
            try await sendError(statusCode: 500, message: "provider config is missing", writer: writer)
            return
        }

        let url = try buildUpstreamURL(baseURL: provider.baseURL, path: request.path, query: request.query)

        var upstreamRequest = URLRequest(url: url)
        upstreamRequest.httpMethod = request.method
        upstreamRequest.httpBody = request.body
        applyForwardedHeaders(from: request, to: &upstreamRequest, apiKey: provider.apiKey)

        let (bytes, response) = try await session.bytes(for: upstreamRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        try await writer.startChunkedResponse(
            statusCode: httpResponse.statusCode,
            headers: forwardedResponseHeaders(from: httpResponse)
        )

        var buffer = Data()
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 4096 {
                try await writer.sendChunk(buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }

        if !buffer.isEmpty {
            try await writer.sendChunk(buffer)
        }

        try await writer.finishChunkedResponse()
    }

    private func sendError(statusCode: Int, message: String, writer: HTTPConnectionWriter) async throws {
        let response = errorResponse(statusCode: statusCode, message: message)
        try await writer.send(
            statusCode: response.statusCode,
            headers: response.headers,
            body: response.body
        )
    }

    private func errorResponse(statusCode: Int, message: String) -> HTTPResponsePayload {
        HTTPResponsePayload(
            statusCode: statusCode,
            headers: ["Content-Type": "application/json"],
            body: Data("""
            {"error":{"message":"\(escapeJSON(message))","type":"invalid_request_error"}}
            """.utf8)
        )
    }

    private func extractModelName(from body: Data) -> String? {
        guard !body.isEmpty else {
            return nil
        }
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }
        return object["model"] as? String
    }

    private func isAuthorized(request: HTTPRequest) -> Bool {
        guard let authorization = request.headers["authorization"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !authorization.isEmpty else {
            return false
        }

        if authorization == config.app.apiKey {
            return true
        }

        let lowercased = authorization.lowercased()
        guard lowercased.hasPrefix("bearer ") else {
            return false
        }

        let token = String(authorization.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
        return token == config.app.apiKey
    }

    private func applyForwardedHeaders(from request: HTTPRequest, to upstreamRequest: inout URLRequest, apiKey: String) {
        let blockedHeaders: Set<String> = [
            "authorization",
            "connection",
            "content-length",
            "host",
            "transfer-encoding",
        ]

        for headerName in request.headers.keys.sorted() {
            guard !blockedHeaders.contains(headerName), let value = request.headers[headerName] else {
                continue
            }
            upstreamRequest.setValue(value, forHTTPHeaderField: headerName)
        }

        upstreamRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    }

    private func forwardedResponseHeaders(from response: HTTPURLResponse) -> [String: String] {
        var headers: [String: String] = [:]
        let blockedHeaders: Set<String> = [
            "connection",
            "content-length",
            "transfer-encoding",
        ]

        for (rawName, rawValue) in response.allHeaderFields {
            guard let name = rawName as? String, let value = rawValue as? String else {
                continue
            }
            guard !blockedHeaders.contains(name.lowercased()) else {
                continue
            }
            headers[name] = value
        }

        return headers
    }

    private func buildUpstreamURL(baseURL: URL, path: String, query: String?) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw ConfigError.invalidURL(baseURL.absoluteString)
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let requestPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, requestPath].filter { !$0.isEmpty }.joined(separator: "/")
        components.percentEncodedQuery = query

        guard let url = components.url else {
            throw ConfigError.invalidURL(baseURL.absoluteString)
        }
        return url
    }

    private func escapeJSON(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
