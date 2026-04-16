import Foundation

protocol CLICommand {
    static var name: String { get }
    static var summary: String { get }

    init(arguments: ArraySlice<String>) throws
    func run() async throws
}

enum ParseResult {
    case help
    case command(any CLICommand)
}

struct CommandParser {
    let commandTypes: [CLICommand.Type]
    let defaultCommand: CLICommand.Type

    func parse(arguments: [String]) throws -> ParseResult {
        guard let commandName = arguments.first else {
            return .command(try defaultCommand.init(arguments: []))
        }

        switch commandName {
        case "-h", "--help", "help":
            return .help
        default:
            guard let commandType = commandTypes.first(where: { $0.name == commandName }) else {
                throw CLIError.unknownCommand(commandName)
            }
            return .command(try commandType.init(arguments: arguments.dropFirst()))
        }
    }

    var usage: String {
        let commands = commandTypes
            .map { "  \($0.name)    \($0.summary)" }
            .joined(separator: "\n")

        return """
        usage: llmswitch [command]

        commands:
        \(commands)

        If no command is provided, `serve` is used.
        """
    }
}
