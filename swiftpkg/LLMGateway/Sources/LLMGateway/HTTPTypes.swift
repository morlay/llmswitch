import Foundation

// MARK: - HTTP 请求

public struct HTTPRequest: Equatable, Sendable {
    public let method: String
    public let target: String
    public let version: String
    public let headers: [String: String]
    public let body: Data

    public init(
        method: String,
        target: String,
        version: String,
        headers: [String: String],
        body: Data
    ) {
        self.method = method
        self.target = target
        self.version = version
        self.headers = headers
        self.body = body
    }

    /// 请求路径（不含查询参数）
    public var path: String {
        String(
            target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        )
    }

    /// 查询参数字符串
    public var query: String? {
        let components = target.split(
            separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        guard components.count == 2 else {
            return nil
        }
        return String(components[1])
    }

    /// 从请求 body 中提取 model 字段
    public func extractModelFromBody() -> String? {
        guard !body.isEmpty else {
            return nil
        }
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }
        return object["model"] as? String
    }

    /// 尝试将 body 解码为 JSON 字典
    public func bodyJSON() -> [String: Any]? {
        guard !body.isEmpty else { return nil }
        return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
    }

    // MARK: - 解析

    static let headerDelimiter = Data("\r\n\r\n".utf8)

    public static func parse(_ rawRequest: Data) throws -> HTTPRequest {
        guard let headerRange = rawRequest.range(of: headerDelimiter) else {
            throw HTTPError.invalidRequest("缺少 HTTP header 分隔符")
        }

        let headerData = rawRequest[..<headerRange.lowerBound]
        let body = rawRequest[headerRange.upperBound...]

        guard let headerString = String(data: headerData, encoding: .utf8) else {
            throw HTTPError.invalidRequest("header 不是有效的 UTF-8")
        }

        var lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            throw HTTPError.invalidRequest("缺少请求行")
        }

        lines.removeFirst()

        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3 else {
            throw HTTPError.invalidRequest("无效的请求行")
        }

        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let separator = line.firstIndex(of: ":") else {
                throw HTTPError.invalidRequest("无效的 header 行")
            }
            let name = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(
                in: .whitespacesAndNewlines)
            headers[name] = value
        }

        return HTTPRequest(
            method: String(parts[0]),
            target: String(parts[1]),
            version: String(parts[2]),
            headers: headers,
            body: Data(body)
        )
    }

    public static func contentLength(fromHeaderPrefix data: Data) throws -> Int {
        guard let headerRange = data.range(of: headerDelimiter) else {
            return 0
        }

        let headerData = data[..<headerRange.lowerBound]
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            throw HTTPError.invalidRequest("header 不是有效的 UTF-8")
        }

        for line in headerString.components(separatedBy: "\r\n").dropFirst() where !line.isEmpty {
            guard let separator = line.firstIndex(of: ":") else {
                continue
            }
            let name = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard name == "content-length" else {
                continue
            }
            let value = line[line.index(after: separator)...].trimmingCharacters(
                in: .whitespacesAndNewlines)
            guard let contentLength = Int(value), contentLength >= 0 else {
                throw HTTPError.invalidRequest("无效的 content-length")
            }
            return contentLength
        }

        return 0
    }
}

// MARK: - HTTP 响应负载

public struct HTTPResponsePayload: Equatable, Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String], body: Data) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

// MARK: - HTTP 错误

public enum HTTPError: LocalizedError, Sendable {
    case invalidRequest(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRequest(let message):
            return "HTTP 请求错误: \(message)"
        }
    }
}

// MARK: - 工具函数

func reasonPhrase(for statusCode: Int) -> String {
    switch statusCode {
    case 200: return "OK"
    case 201: return "Created"
    case 400: return "Bad Request"
    case 401: return "Unauthorized"
    case 404: return "Not Found"
    case 405: return "Method Not Allowed"
    case 500: return "Internal Server Error"
    case 502: return "Bad Gateway"
    default: return "HTTP \(statusCode)"
    }
}

func escapeJSON(_ value: String) -> String {
    value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\r", with: "\\r")
}
