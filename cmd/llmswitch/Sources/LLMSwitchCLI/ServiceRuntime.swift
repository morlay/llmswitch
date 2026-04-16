import Foundation
import LLMSwitchCore

struct ServiceRuntime: Sendable {
    let paths: AppPaths
    let config: AppConfig
    let proxy: ProxyService
    let notices: [String]

    static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> Self {
        let paths = AppPaths(configRoot: AppPaths.defaultRoot(environment: environment, fileManager: fileManager))
        try paths.ensureDirectories(fileManager: fileManager)

        var notices: [String] = []
        if try ensureBootstrapConfigExists(paths: paths, fileManager: fileManager) {
            notices.append("created default config at \(paths.configFile.path)")
        }
        if try migrateMissingAppAPIKeyIfNeeded(paths: paths, fileManager: fileManager) {
            notices.append("generated missing app apiKey in \(paths.configFile.path)")
        }

        let config = try ConfigStore(paths: paths).load()
        let state = try StateStore(paths: paths).load()
        let cacheStore = CacheStore(paths: paths)
        let snapshots = try cacheStore.loadAll(providerNames: Array(config.providers.keys))

        let sessionConfiguration = URLSessionConfiguration.default
        sessionConfiguration.timeoutIntervalForRequest = TimeInterval(config.app.requestTimeoutSeconds)
        sessionConfiguration.timeoutIntervalForResource = TimeInterval(config.app.requestTimeoutSeconds)
        let session = URLSession(configuration: sessionConfiguration)

        let providerClient = ProviderClient(session: session)
        let proxy = ProxyService(
            config: config,
            state: state,
            cacheStore: cacheStore,
            providerClient: providerClient,
            session: session,
            snapshots: snapshots
        )

        return Self(paths: paths, config: config, proxy: proxy, notices: notices)
    }

    private static func ensureBootstrapConfigExists(
        paths: AppPaths,
        fileManager: FileManager
    ) throws -> Bool {
        guard !fileManager.fileExists(atPath: paths.configFile.path) else {
            return false
        }

        let config = SampleConfig.defaultConfig(serviceAPIKey: generateServiceAPIKey())
        try ConfigStore(paths: paths).save(config)
        return true
    }

    private static func migrateMissingAppAPIKeyIfNeeded(
        paths: AppPaths,
        fileManager: FileManager
    ) throws -> Bool {
        guard fileManager.fileExists(atPath: paths.configFile.path) else {
            return false
        }

        let source = try String(contentsOf: paths.configFile, encoding: .utf8)
        let document = try TOMLParser.parse(source)
        guard let appTable = document.table(at: ["app"]), appTable["apiKey"] == nil else {
            return false
        }

        let generatedKey = generateServiceAPIKey()
        var outputLines: [String] = []
        var inserted = false
        var inAppSection = false

        for line in source.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                if inAppSection && !inserted {
                    outputLines.append("apiKey = \"\(generatedKey)\"")
                    inserted = true
                }
                inAppSection = trimmed == "[app]"
            }
            outputLines.append(line)
        }

        if inAppSection && !inserted {
            outputLines.append("apiKey = \"\(generatedKey)\"")
        }

        try outputLines.joined(separator: "\n").write(to: paths.configFile, atomically: true, encoding: .utf8)
        return true
    }

    private static func generateServiceAPIKey() -> String {
        "llmsw_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}
