import Foundation

public struct ProviderModel: Codable, Equatable, Sendable {
    public let id: String
    public let object: String?
    public let ownedBy: String?
    public let capabilities: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case object
        case ownedBy = "owned_by"
        case capabilities
        case features
        case supportedEndpoints = "supported_endpoints"
        case endpoints
        case inputModalities = "input_modalities"
        case outputModalities = "output_modalities"
    }

    public init(id: String, object: String? = nil, ownedBy: String? = nil, capabilities: [String] = []) {
        self.id = id
        self.object = object
        self.ownedBy = ownedBy
        self.capabilities = capabilities
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        object = try container.decodeIfPresent(String.self, forKey: .object)
        ownedBy = try container.decodeIfPresent(String.self, forKey: .ownedBy)

        let capabilitiesField = try container.decodeIfPresent([String].self, forKey: .capabilities) ?? []
        let featuresField = try container.decodeIfPresent([String].self, forKey: .features) ?? []
        let supportedEndpointsField = try container.decodeIfPresent([String].self, forKey: .supportedEndpoints) ?? []
        let endpointsField = try container.decodeIfPresent([String].self, forKey: .endpoints) ?? []
        let inputModalitiesField = try container.decodeIfPresent([String].self, forKey: .inputModalities) ?? []
        let outputModalitiesField = try container.decodeIfPresent([String].self, forKey: .outputModalities) ?? []
        let allCapabilities = [
            capabilitiesField,
            featuresField,
            supportedEndpointsField,
            endpointsField,
            inputModalitiesField,
            outputModalitiesField,
        ]
        let flattenedCapabilities = Array(allCapabilities.joined())
        capabilities = Array(NSOrderedSet(array: flattenedCapabilities)) as? [String] ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(object, forKey: .object)
        try container.encodeIfPresent(ownedBy, forKey: .ownedBy)
        if !capabilities.isEmpty {
            try container.encode(capabilities, forKey: .capabilities)
        }
    }
}

public struct ProviderCacheMeta: Codable, Equatable, Sendable {
    public let providerName: String
    public let fetchedAt: Date
    public let wasSuccessful: Bool
    public let errorMessage: String?

    public init(providerName: String, fetchedAt: Date, wasSuccessful: Bool, errorMessage: String?) {
        self.providerName = providerName
        self.fetchedAt = fetchedAt
        self.wasSuccessful = wasSuccessful
        self.errorMessage = errorMessage
    }
}

public struct ProviderCacheSnapshot: Equatable, Sendable {
    public let meta: ProviderCacheMeta
    public let models: [ProviderModel]

    public init(meta: ProviderCacheMeta, models: [ProviderModel]) {
        self.meta = meta
        self.models = models
    }
}

public struct CacheStore: Sendable {
    public let paths: AppPaths

    public init(paths: AppPaths) {
        self.paths = paths
    }

    public func loadAll(providerNames: [String]? = nil) throws -> [String: ProviderCacheSnapshot] {
        let names = providerNames ?? []
        if providerNames == nil {
            guard FileManager.default.fileExists(atPath: paths.cacheRoot.path) else {
                return [:]
            }

            let entries = try FileManager.default.contentsOfDirectory(
                at: paths.cacheRoot,
                includingPropertiesForKeys: nil
            )

            return try entries.reduce(into: [String: ProviderCacheSnapshot]()) { partialResult, url in
                let providerName = url.lastPathComponent
                if let snapshot = try load(providerName: providerName) {
                    partialResult[providerName] = snapshot
                }
            }
        }

        return try names.reduce(into: [String: ProviderCacheSnapshot]()) { partialResult, name in
            if let snapshot = try load(providerName: name) {
                partialResult[name] = snapshot
            }
        }
    }

    public func load(providerName: String) throws -> ProviderCacheSnapshot? {
        let metaURL = paths.metaCacheFile(for: providerName)
        guard FileManager.default.fileExists(atPath: metaURL.path) else {
            return nil
        }

        let decoder = Self.makeDecoder()
        let meta = try decoder.decode(ProviderCacheMeta.self, from: Data(contentsOf: metaURL))

        let modelsURL = paths.modelsCacheFile(for: providerName)
        let models: [ProviderModel]
        if FileManager.default.fileExists(atPath: modelsURL.path) {
            models = try decoder.decode([ProviderModel].self, from: Data(contentsOf: modelsURL))
        } else {
            models = []
        }

        return ProviderCacheSnapshot(meta: meta, models: models)
    }

    public func saveSuccess(providerName: String, models: [ProviderModel], fetchedAt: Date = Date()) throws {
        let directory = paths.cacheDirectory(for: providerName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = Self.makeEncoder()
        let meta = ProviderCacheMeta(
            providerName: providerName,
            fetchedAt: fetchedAt,
            wasSuccessful: true,
            errorMessage: nil
        )

        try encoder.encode(models).write(to: paths.modelsCacheFile(for: providerName))
        try encoder.encode(meta).write(to: paths.metaCacheFile(for: providerName))
    }

    public func saveFailure(providerName: String, errorMessage: String, fetchedAt: Date = Date()) throws {
        let directory = paths.cacheDirectory(for: providerName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = Self.makeEncoder()
        let meta = ProviderCacheMeta(
            providerName: providerName,
            fetchedAt: fetchedAt,
            wasSuccessful: false,
            errorMessage: errorMessage
        )
        try encoder.encode(meta).write(to: paths.metaCacheFile(for: providerName))
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
