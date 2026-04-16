import Foundation

// MARK: - 访问日志条目

public struct AccessLogEntry: Sendable {
    public let timestamp: Date
    public let method: String
    public let path: String
    public let statusCode: Int
    public let latencyMs: Int64
    public let model: String?
    public let target: String?
    public let clientIP: String
    public let errorMessage: String?
    public let userAgent: String?

    public init(
        timestamp: Date = Date(),
        method: String,
        path: String,
        statusCode: Int,
        latencyMs: Int64,
        model: String? = nil,
        target: String? = nil,
        clientIP: String = "127.0.0.1",
        errorMessage: String? = nil,
        userAgent: String? = nil
    ) {
        self.timestamp = timestamp
        self.method = method
        self.path = path
        self.statusCode = statusCode
        self.latencyMs = latencyMs
        self.model = model
        self.target = target
        self.clientIP = clientIP
        self.errorMessage = errorMessage
        self.userAgent = userAgent
    }

    public var formattedLine: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let ts = formatter.string(from: timestamp)

        var parts = [
            ts,
            clientIP,
            method,
            path,
            "\(statusCode)",
            "\(latencyMs)ms",
        ]

        if let model { parts.append("model=\(model)") }
        if let target { parts.append("target=\(target)") }
        if let ua = userAgent { parts.append("ua=\(ua)") }
        if let errorMessage { parts.append("error=\(errorMessage)") }

        return parts.joined(separator: " ")
    }
}

// MARK: - 访问日志记录器

public actor GatewayLogger {
    private let verbose: Bool

    public init(verbose: Bool = false) {
        self.verbose = verbose
    }

    public func log(_ entry: AccessLogEntry) {
        let line = entry.formattedLine

        if entry.statusCode >= 400 {
            fputs("[\(entry.statusCode)] \(line)\n", stderr)
        } else {
            print(line)
        }
    }

    public func logRequest(_ raw: String) {
        guard verbose else { return }
        fputs("\n>>> REQUEST >>>\n\(raw)\n<<< END REQUEST <<<\n", stderr)
    }

    public func logResponseHead(_ raw: String) {
        guard verbose else { return }
        fputs("\n<<< RESPONSE <<<\n\(raw)\n", stderr)
    }

    public func info(_ message: String) {
        guard verbose else { return }
        fputs("[info] \(message)\n", stderr)
    }
}
