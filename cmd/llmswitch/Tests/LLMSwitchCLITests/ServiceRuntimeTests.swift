import Foundation
import Testing
import LLMSwitchCore
@testable import LLMSwitchCLI

@Test func runtimeCreatesBootstrapConfigWhenMissing() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: root)
    }

    let runtime = try ServiceRuntime.load(environment: [
        "LLMSWITCH_CONFIG_ROOT": root.path,
    ])

    #expect(FileManager.default.fileExists(atPath: runtime.paths.configFile.path))
    #expect(runtime.config.app.listen == "127.0.0.1:8787")
    #expect(runtime.config.app.apiKey.hasPrefix("llmsw_"))
    #expect(runtime.notices.contains("created default config at \(runtime.paths.configFile.path)"))
}

@Test func runtimeMigratesMissingAppAPIKey() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer {
        try? FileManager.default.removeItem(at: root)
    }

    let paths = AppPaths(configRoot: root)
    try paths.ensureDirectories()
    try """
    [app]
    listen = "127.0.0.1:8787"
    modelRefreshIntervalSeconds = 300
    requestTimeoutSeconds = 600

    [providers]
    """.write(to: paths.configFile, atomically: true, encoding: .utf8)

    let runtime = try ServiceRuntime.load(environment: [
        "LLMSWITCH_CONFIG_ROOT": root.path,
    ])
    let source = try String(contentsOf: paths.configFile, encoding: .utf8)

    #expect(runtime.config.app.apiKey.hasPrefix("llmsw_"))
    #expect(source.contains("apiKey = \""))
    #expect(runtime.notices.contains("generated missing app apiKey in \(runtime.paths.configFile.path)"))
}
