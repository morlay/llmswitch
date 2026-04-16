import Foundation

public struct AppPaths: Sendable {
    public let configRoot: URL

    public init(configRoot: URL) {
        self.configRoot = configRoot.standardizedFileURL
    }

    public static func defaultRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL {
        if let override = environment["LLMSWITCH_CONFIG_ROOT"], !override.isEmpty {
            return URL(
                fileURLWithPath: NSString(string: override).expandingTildeInPath,
                isDirectory: true
            )
        }

        return fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("llmswitch", isDirectory: true)
    }

    public var configFile: URL {
        configRoot.appendingPathComponent("config.toml", isDirectory: false)
    }

    public var stateFile: URL {
        configRoot.appendingPathComponent("state.toml", isDirectory: false)
    }

    public var cacheRoot: URL {
        configRoot.appendingPathComponent("cache", isDirectory: true)
    }

    public func cacheDirectory(for providerName: String) -> URL {
        cacheRoot.appendingPathComponent(Self.sanitize(providerName), isDirectory: true)
    }

    public func modelsCacheFile(for providerName: String) -> URL {
        cacheDirectory(for: providerName).appendingPathComponent("models.json", isDirectory: false)
    }

    public func metaCacheFile(for providerName: String) -> URL {
        cacheDirectory(for: providerName).appendingPathComponent("meta.json", isDirectory: false)
    }

    public func ensureDirectories(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: configRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
    }

    private static func sanitize(_ providerName: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        return providerName.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }.reduce(into: "") { partialResult, character in
            partialResult.append(character)
        }
    }
}
