import Foundation
import Testing
@testable import LLMSwitchCLI

@Test func parserDefaultsToServe() throws {
    let parser = CommandParser(
        commandTypes: [ServeCommand.self],
        defaultCommand: ServeCommand.self
    )

    let result = try parser.parse(arguments: [])
    switch result {
    case .help:
        throw NSError(domain: "LLMSwitchCLI", code: 1, userInfo: [NSLocalizedDescriptionKey: "expected serve command"])
    case let .command(command):
        #expect(command is ServeCommand)
    }
}

@Test func parserShowsHelp() throws {
    let parser = CommandParser(
        commandTypes: [ServeCommand.self],
        defaultCommand: ServeCommand.self
    )

    let result = try parser.parse(arguments: ["help"])
    switch result {
    case .help:
        return
    case .command:
        throw NSError(domain: "LLMSwitchCLI", code: 1, userInfo: [NSLocalizedDescriptionKey: "expected help result"])
    }
}

@Test func parserRejectsUnknownCommand() throws {
    let parser = CommandParser(
        commandTypes: [ServeCommand.self],
        defaultCommand: ServeCommand.self
    )

    do {
        _ = try parser.parse(arguments: ["refresh-models"])
        throw NSError(domain: "LLMSwitchCLI", code: 1, userInfo: [NSLocalizedDescriptionKey: "expected parse failure"])
    } catch let error as CLIError {
        #expect(error == .unknownCommand("refresh-models"))
    }
}

@Test func serveRejectsUnexpectedArguments() throws {
    do {
        _ = try ServeCommand(arguments: ["extra"])
        throw NSError(domain: "LLMSwitchCLI", code: 1, userInfo: [NSLocalizedDescriptionKey: "expected parse failure"])
    } catch let error as CLIError {
        #expect(error == .unexpectedArguments(command: "serve", arguments: ["extra"]))
    }
}
