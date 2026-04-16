import Foundation

public enum TOMLValue: Equatable, Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case table([String: TOMLValue])

    public var stringValue: String? {
        guard case let .string(value) = self else {
            return nil
        }
        return value
    }

    public var intValue: Int? {
        guard case let .int(value) = self else {
            return nil
        }
        return value
    }

    public var boolValue: Bool? {
        guard case let .bool(value) = self else {
            return nil
        }
        return value
    }

    public var tableValue: [String: TOMLValue]? {
        guard case let .table(value) = self else {
            return nil
        }
        return value
    }
}

public struct TOMLDocument: Equatable, Sendable {
    public var root: [String: TOMLValue]

    public init(root: [String: TOMLValue] = [:]) {
        self.root = root
    }

    public func value(at path: [String]) -> TOMLValue? {
        guard !path.isEmpty else {
            return .table(root)
        }

        var current: TOMLValue = .table(root)
        for part in path {
            guard let table = current.tableValue, let next = table[part] else {
                return nil
            }
            current = next
        }
        return current
    }

    public func table(at path: [String]) -> [String: TOMLValue]? {
        value(at: path)?.tableValue
    }

    mutating func ensureTable(at path: [String]) throws {
        try Self.ensureTable(at: path, in: &root)
    }

    mutating func set(_ value: TOMLValue, at path: [String]) throws {
        try Self.insert(value, at: path, in: &root)
    }

    private static func ensureTable(at path: [String], in table: inout [String: TOMLValue]) throws {
        guard let head = path.first else {
            return
        }

        if path.count == 1 {
            switch table[head] {
            case .none:
                table[head] = .table([:])
            case .some(.table):
                return
            case .some:
                throw TOMLError.typeMismatch(path: path)
            }
            return
        }

        var nestedTable: [String: TOMLValue]
        switch table[head] {
        case let .some(.table(existing)):
            nestedTable = existing
        case .none:
            nestedTable = [:]
        case .some:
            throw TOMLError.typeMismatch(path: path)
        }

        try ensureTable(at: Array(path.dropFirst()), in: &nestedTable)
        table[head] = .table(nestedTable)
    }

    private static func insert(_ value: TOMLValue, at path: [String], in table: inout [String: TOMLValue]) throws {
        guard let head = path.first else {
            return
        }

        if path.count == 1 {
            table[head] = value
            return
        }

        var nestedTable: [String: TOMLValue]
        switch table[head] {
        case let .some(.table(existing)):
            nestedTable = existing
        case .none:
            nestedTable = [:]
        case .some:
            throw TOMLError.typeMismatch(path: path)
        }

        try insert(value, at: Array(path.dropFirst()), in: &nestedTable)
        table[head] = .table(nestedTable)
    }
}

public enum TOMLError: LocalizedError, Sendable {
    case invalidLine(number: Int, content: String)
    case invalidKey(number: Int, content: String)
    case invalidValue(number: Int, content: String)
    case typeMismatch(path: [String])

    public var errorDescription: String? {
        switch self {
        case let .invalidLine(number, content):
            return "Invalid TOML line \(number): \(content)"
        case let .invalidKey(number, content):
            return "Invalid TOML key at line \(number): \(content)"
        case let .invalidValue(number, content):
            return "Invalid TOML value at line \(number): \(content)"
        case let .typeMismatch(path):
            return "TOML path \(path.joined(separator: ".")) collides with a scalar value"
        }
    }
}

public enum TOMLParser {
    public static func parse(_ source: String) throws -> TOMLDocument {
        var document = TOMLDocument()
        var currentTablePath: [String] = []

        for (index, rawLine) in source.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNumber = index + 1
            let cleanedLine = try stripComment(from: String(rawLine)).trimmingCharacters(in: .whitespaces)
            guard !cleanedLine.isEmpty else {
                continue
            }

            if cleanedLine.hasPrefix("[") {
                guard cleanedLine.hasSuffix("]") else {
                    throw TOMLError.invalidLine(number: lineNumber, content: cleanedLine)
                }
                let body = String(cleanedLine.dropFirst().dropLast())
                let path = try parseKeyPath(body, lineNumber: lineNumber)
                try document.ensureTable(at: path)
                currentTablePath = path
                continue
            }

            guard let separatorIndex = try findUnquotedEquals(in: cleanedLine) else {
                throw TOMLError.invalidLine(number: lineNumber, content: cleanedLine)
            }

            let rawKey = String(cleanedLine[..<separatorIndex]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(cleanedLine[cleanedLine.index(after: separatorIndex)...]).trimmingCharacters(in: .whitespaces)

            let keyPath = try parseKeyPath(rawKey, lineNumber: lineNumber)
            let value = try parseValue(rawValue, lineNumber: lineNumber)
            try document.set(value, at: currentTablePath + keyPath)
        }

        return document
    }

    private static func stripComment(from line: String) throws -> String {
        var result = ""
        var inQuotes = false
        var isEscaped = false

        for character in line {
            if isEscaped {
                result.append(character)
                isEscaped = false
                continue
            }

            if character == "\\" && inQuotes {
                result.append(character)
                isEscaped = true
                continue
            }

            if character == "\"" {
                inQuotes.toggle()
                result.append(character)
                continue
            }

            if character == "#" && !inQuotes {
                break
            }

            result.append(character)
        }

        if inQuotes {
            throw TOMLError.invalidLine(number: 0, content: line)
        }

        return result
    }

    private static func findUnquotedEquals(in line: String) throws -> String.Index? {
        var inQuotes = false
        var isEscaped = false

        for index in line.indices {
            let character = line[index]
            if isEscaped {
                isEscaped = false
                continue
            }
            if character == "\\" && inQuotes {
                isEscaped = true
                continue
            }
            if character == "\"" {
                inQuotes.toggle()
                continue
            }
            if character == "=" && !inQuotes {
                return index
            }
        }

        if inQuotes {
            throw TOMLError.invalidLine(number: 0, content: line)
        }

        return nil
    }

    private static func parseKeyPath(_ input: String, lineNumber: Int) throws -> [String] {
        var parts: [String] = []
        var buffer = ""
        var inQuotes = false
        var isEscaped = false

        for character in input {
            if isEscaped {
                buffer.append(character)
                isEscaped = false
                continue
            }

            if character == "\\" && inQuotes {
                isEscaped = true
                continue
            }

            if character == "\"" {
                inQuotes.toggle()
                continue
            }

            if character == "." && !inQuotes {
                let key = buffer.trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty else {
                    throw TOMLError.invalidKey(number: lineNumber, content: input)
                }
                parts.append(key)
                buffer.removeAll(keepingCapacity: true)
                continue
            }

            buffer.append(character)
        }

        let key = buffer.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !inQuotes else {
            throw TOMLError.invalidKey(number: lineNumber, content: input)
        }
        parts.append(key)
        return parts
    }

    private static func parseValue(_ input: String, lineNumber: Int) throws -> TOMLValue {
        guard !input.isEmpty else {
            throw TOMLError.invalidValue(number: lineNumber, content: input)
        }

        if input.hasPrefix("\""), input.hasSuffix("\"") {
            return .string(try unescapeString(String(input.dropFirst().dropLast()), lineNumber: lineNumber))
        }

        if input == "true" {
            return .bool(true)
        }

        if input == "false" {
            return .bool(false)
        }

        if let intValue = Int(input) {
            return .int(intValue)
        }

        throw TOMLError.invalidValue(number: lineNumber, content: input)
    }

    private static func unescapeString(_ input: String, lineNumber: Int) throws -> String {
        var result = ""
        var isEscaped = false

        for character in input {
            if isEscaped {
                switch character {
                case "\\":
                    result.append("\\")
                case "\"":
                    result.append("\"")
                case "n":
                    result.append("\n")
                case "t":
                    result.append("\t")
                default:
                    throw TOMLError.invalidValue(number: lineNumber, content: input)
                }
                isEscaped = false
                continue
            }

            if character == "\\" {
                isEscaped = true
                continue
            }

            result.append(character)
        }

        if isEscaped {
            throw TOMLError.invalidValue(number: lineNumber, content: input)
        }

        return result
    }
}
