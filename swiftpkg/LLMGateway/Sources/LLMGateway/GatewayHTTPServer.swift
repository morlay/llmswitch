import Foundation
import Network

// MARK: - HTTP 响应写入协议

public protocol HTTPResponseWriter: AnyObject, Sendable {
    func send(statusCode: Int, headers: [String: String], body: Data) async throws
    func startChunkedResponse(statusCode: Int, headers: [String: String]) async throws
    func sendChunk(_ data: Data) async throws
    func finishChunkedResponse() async throws
}

// MARK: - HTTP 连接写入器

public final class HTTPConnectionWriter: HTTPResponseWriter, @unchecked Sendable {
    private let connection: NWConnection

    init(connection: NWConnection) {
        self.connection = connection
    }

    public func send(statusCode: Int, headers: [String: String], body: Data) async throws {
        var mergedHeaders = headers
        mergedHeaders["Connection"] = "close"
        mergedHeaders["Content-Length"] = String(body.count)

        try await sendRaw(
            data: Data(makeResponseHead(statusCode: statusCode, headers: mergedHeaders).utf8))
        if !body.isEmpty {
            try await sendRaw(data: body)
        }
        connection.cancel()
    }

    public func startChunkedResponse(statusCode: Int, headers: [String: String]) async throws {
        var mergedHeaders = headers
        mergedHeaders["Connection"] = "close"
        mergedHeaders["Transfer-Encoding"] = "chunked"
        mergedHeaders.removeValue(forKey: "Content-Length")

        try await sendRaw(
            data: Data(makeResponseHead(statusCode: statusCode, headers: mergedHeaders).utf8))
    }

    public func sendChunk(_ data: Data) async throws {
        guard !data.isEmpty else { return }
        let prefix = Data("\(String(data.count, radix: 16))\r\n".utf8)
        let suffix = Data("\r\n".utf8)
        try await sendRaw(data: prefix + data + suffix)
    }

    public func finishChunkedResponse() async throws {
        try await sendRaw(data: Data("0\r\n\r\n".utf8))
        connection.cancel()
    }

    public func sendSSEEvent(_ text: String) async throws {
        guard !text.isEmpty else { return }
        let data = Data("\(text)\n\n".utf8)
        try await sendRaw(data: data)
    }

    public func close() {
        connection.cancel()
    }

    private func makeResponseHead(statusCode: Int, headers: [String: String]) -> String {
        var lines = ["HTTP/1.1 \(statusCode) \(reasonPhrase(for: statusCode))"]
        for name in headers.keys.sorted() {
            guard let value = headers[name] else { continue }
            lines.append("\(name): \(value)")
        }
        lines.append("")
        lines.append("")
        return lines.joined(separator: "\r\n")
    }

    private func sendRaw(data: Data) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            connection.send(
                content: data,
                completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                })
        }
    }
}

// MARK: - HTTP 服务器

public final class GatewayHTTPServer: @unchecked Sendable {
    public typealias Handler = @Sendable (HTTPRequest, HTTPConnectionWriter) async -> Void

    private let listenAddress: ListenAddress
    private let handler: Handler
    private let queue = DispatchQueue(label: "com.llmswitch.gateway-server")
    private var listener: NWListener?

    public init(listenAddress: ListenAddress, handler: @escaping Handler) {
        self.listenAddress = listenAddress
        self.handler = handler
    }

    public func start() throws {
        let port = NWEndpoint.Port(
            integerLiteral: NWEndpoint.Port.IntegerLiteralType(listenAddress.port))
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(
            host: NWEndpoint.Host(listenAddress.host),
            port: port
        )

        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                fputs("llmswitch server 错误: \(error)\n", stderr)
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)

        Task {
            let writer = HTTPConnectionWriter(connection: connection)
            do {
                let rawRequest = try await receiveRequestData(from: connection)
                let request = try HTTPRequest.parse(rawRequest)
                await handler(request, writer)
            } catch {
                let payload = Data(
                    """
                    {"error":{"message":"\(escapeJSON(error.localizedDescription))","type":"invalid_request_error"}}
                    """.utf8)
                try? await writer.send(
                    statusCode: 400, headers: ["Content-Type": "application/json"], body: payload)
            }
        }
    }

    private func receiveRequestData(from connection: NWConnection) async throws -> Data {
        var buffer = Data()
        var expectedTotalLength: Int?

        while true {
            let chunk = try await receiveChunk(from: connection)
            if chunk.isEmpty {
                if let expectedTotalLength, buffer.count >= expectedTotalLength {
                    return Data(buffer.prefix(expectedTotalLength))
                }
                throw HTTPError.invalidRequest("连接在请求完成前关闭")
            }

            buffer.append(chunk)

            if expectedTotalLength == nil, let range = buffer.range(of: HTTPRequest.headerDelimiter)
            {
                let headerLength = range.upperBound
                let bodyLength = try HTTPRequest.contentLength(fromHeaderPrefix: buffer)
                expectedTotalLength = headerLength + bodyLength
            }

            if let expectedTotalLength, buffer.count >= expectedTotalLength {
                return Data(buffer.prefix(expectedTotalLength))
            }
        }
    }

    private func receiveChunk(from connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
                data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                    return
                }
                if isComplete {
                    continuation.resume(returning: Data())
                    return
                }
                continuation.resume(returning: Data())
            }
        }
    }
}
