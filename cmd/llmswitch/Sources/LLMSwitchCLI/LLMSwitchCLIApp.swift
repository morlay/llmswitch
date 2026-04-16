import Foundation

@main
struct LLMSwitchCLIApp {
    static func main() async {
        let parser = CommandParser(
            commandTypes: [ServeCommand.self],
            defaultCommand: ServeCommand.self
        )

        do {
            switch try parser.parse(arguments: Array(CommandLine.arguments.dropFirst())) {
            case .help:
                print(parser.usage)
            case let .command(command):
                try await command.run()
            }
        } catch let error as CLIError {
            fputs("llmswitch: \(error.localizedDescription)\n\n\(parser.usage)\n", stderr)
            exit(1)
        } catch {
            fputs("llmswitch failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
