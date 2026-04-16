import Foundation

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

    public var path: String {
        String(target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
    }

    public var query: String? {
        let components = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        guard components.count == 2 else {
            return nil
        }
        return String(components[1])
    }

    static let headerDelimiter = Data("\r\n\r\n".utf8)

    public static func parse(_ rawRequest: Data) throws -> HTTPRequest {
        guard let headerRange = rawRequest.range(of: headerDelimiter) else {
            throw HTTPError.invalidRequest("missing HTTP header delimiter")
        }

        let headerData = rawRequest[..<headerRange.lowerBound]
        let body = rawRequest[headerRange.upperBound...]

        guard let headerString = String(data: headerData, encoding: .utf8) else {
            throw HTTPError.invalidRequest("header is not valid UTF-8")
        }

        var lines = headerString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            throw HTTPError.invalidRequest("missing request line")
        }

        lines.removeFirst()

        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3 else {
            throw HTTPError.invalidRequest("invalid request line")
        }

        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let separator = line.firstIndex(of: ":") else {
                throw HTTPError.invalidRequest("invalid header line")
            }
            let name = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
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
            throw HTTPError.invalidRequest("header is not valid UTF-8")
        }

        for line in headerString.components(separatedBy: "\r\n").dropFirst() where !line.isEmpty {
            guard let separator = line.firstIndex(of: ":") else {
                continue
            }
            let name = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard name == "content-length" else {
                continue
            }
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard let contentLength = Int(value), contentLength >= 0 else {
                throw HTTPError.invalidRequest("invalid content-length")
            }
            return contentLength
        }

        return 0
    }
}

public enum HTTPError: LocalizedError, Sendable {
    case invalidRequest(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidRequest(message):
            return "HTTP request error: \(message)"
        }
    }
}

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

func reasonPhrase(for statusCode: Int) -> String {
    switch statusCode {
    case 200: return "OK"
    case 400: return "Bad Request"
    case 404: return "Not Found"
    case 405: return "Method Not Allowed"
    case 500: return "Internal Server Error"
    case 502: return "Bad Gateway"
    default: return "HTTP \(statusCode)"
    }
}
