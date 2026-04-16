import Foundation

enum CLIError: LocalizedError, Equatable {
    case unknownCommand(String)
    case unexpectedArguments(command: String, arguments: [String])

    var errorDescription: String? {
        switch self {
        case let .unknownCommand(command):
            return "unknown command: \(command)"
        case let .unexpectedArguments(command, arguments):
            return "\(command) does not accept arguments: \(arguments.joined(separator: " "))"
        }
    }
}
