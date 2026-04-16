import Foundation
import Network

public final class HTTPConnectionWriter: @unchecked Sendable {
    private let connection: NWConnection

    init(connection: NWConnection) {
        self.connection = connection
    }

    public func send(statusCode: Int, headers: [String: String], body: Data) async throws {
        var mergedHeaders = headers
        mergedHeaders["Connection"] = "close"
        mergedHeaders["Content-Length"] = String(body.count)

        try await sendRaw(data: Data(makeHead(statusCode: statusCode, headers: mergedHeaders).utf8))
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

        try await sendRaw(data: Data(makeHead(statusCode: statusCode, headers: mergedHeaders).utf8))
    }

    public func sendChunk(_ data: Data) async throws {
        guard !data.isEmpty else {
            return
        }

        let prefix = Data("\(String(data.count, radix: 16))\r\n".utf8)
        let suffix = Data("\r\n".utf8)
        try await sendRaw(data: prefix + data + suffix)
    }

    public func finishChunkedResponse() async throws {
        try await sendRaw(data: Data("0\r\n\r\n".utf8))
        connection.cancel()
    }

    public func close() {
        connection.cancel()
    }

    private func makeHead(statusCode: Int, headers: [String: String]) -> String {
        var lines = ["HTTP/1.1 \(statusCode) \(reasonPhrase(for: statusCode))"]
        for name in headers.keys.sorted() {
            guard let value = headers[name] else {
                continue
            }
            lines.append("\(name): \(value)")
        }
        lines.append("")
        lines.append("")
        return lines.joined(separator: "\r\n")
    }

    private func sendRaw(data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }
}

public final class HTTPServer: @unchecked Sendable {
    public typealias Handler = @Sendable (HTTPRequest, HTTPConnectionWriter) async -> Void

    private let listenAddress: ListenAddress
    private let handler: Handler
    private let queue = DispatchQueue(label: "com.llmswitch.http-server")
    private var listener: NWListener?

    public init(listenAddress: ListenAddress, handler: @escaping Handler) {
        self.listenAddress = listenAddress
        self.handler = handler
    }

    public func start() throws {
        let port = NWEndpoint.Port(integerLiteral: NWEndpoint.Port.IntegerLiteralType(listenAddress.port))
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
            if case let .failed(error) = state {
                fputs("llmswitch server failed: \(error)\n", stderr)
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
                let payload = Data("""
                {"error":{"message":"\(escapeJSON(error.localizedDescription))","type":"invalid_request_error"}}
                """.utf8)
                try? await writer.send(
                    statusCode: 400,
                    headers: ["Content-Type": "application/json"],
                    body: payload
                )
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
                throw HTTPError.invalidRequest("connection closed before request completed")
            }

            buffer.append(chunk)

            if expectedTotalLength == nil, let range = buffer.range(of: HTTPRequest.headerDelimiter) {
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
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
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

    private func escapeJSON(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
