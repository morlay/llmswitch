import Foundation
import LLMSwitchCore

struct ServeCommand: CLICommand {
    static let name = "serve"
    static let summary = "Start the local proxy service."

    init(arguments: ArraySlice<String>) throws {
        guard arguments.isEmpty else {
            throw CLIError.unexpectedArguments(command: Self.name, arguments: Array(arguments))
        }
    }

    func run() async throws {
        let runtime = try ServiceRuntime.load()

        for notice in runtime.notices {
            fputs("llmswitch: \(notice)\n", stderr)
        }

        let server = HTTPServer(listenAddress: runtime.config.app.listenAddress) { request, writer in
            await runtime.proxy.handle(request, writer: writer)
        }
        try server.start()

        Task {
            await runtime.proxy.refreshModelCatalogs()
        }

        let refreshIntervalSeconds = max(runtime.config.app.modelRefreshIntervalSeconds, 0)
        if refreshIntervalSeconds > 0 {
            Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(refreshIntervalSeconds))
                    guard !Task.isCancelled else {
                        break
                    }
                    await runtime.proxy.refreshModelCatalogs()
                }
            }
        }

        print("llmswitch listening on \(runtime.config.app.listen)")
        _ = server

        while true {
            try? await Task.sleep(for: .seconds(3600))
        }
    }
}
