import Foundation

public struct ResolvedModel: Equatable, Sendable {
    public let publicName: String
    public let providerName: String
    public let upstreamModel: String
    public let providerDisplayName: String

    public init(
        publicName: String,
        providerName: String,
        upstreamModel: String,
        providerDisplayName: String
    ) {
        self.publicName = publicName
        self.providerName = providerName
        self.upstreamModel = upstreamModel
        self.providerDisplayName = providerDisplayName
    }
}

public struct ModelRegistry: Sendable {
    private let modelsByName: [String: ResolvedModel]

    public init(config: AppConfig, state: AppState, snapshots: [String: ProviderCacheSnapshot]) {
        var modelsByName: [String: ResolvedModel] = [:]

        let enabledNames = Set(state.enabledProviderModels.values.flatMap { providerModels in
            providerModels.filter(\.value).map(\.key)
        }).sorted()

        for modelName in enabledNames {
            if let binding = state.activeBindings[modelName],
               let provider = config.providers[binding.provider],
               provider.enabled,
               state.enabledProviderModels[binding.provider]?[binding.upstreamModel] == true,
               snapshots[binding.provider]?.models.contains(where: { $0.id == binding.upstreamModel }) == true {
                modelsByName[modelName] = ResolvedModel(
                    publicName: modelName,
                    providerName: binding.provider,
                    upstreamModel: binding.upstreamModel,
                    providerDisplayName: provider.resolvedDisplayName
                )
                continue
            }

            let candidates = config.providers.keys.sorted().compactMap { providerName -> ResolvedModel? in
                guard let provider = config.providers[providerName], provider.enabled else {
                    return nil
                }
                guard state.enabledProviderModels[providerName]?[modelName] == true else {
                    return nil
                }
                guard snapshots[providerName]?.models.contains(where: { $0.id == modelName }) == true else {
                    return nil
                }
                return ResolvedModel(
                    publicName: modelName,
                    providerName: providerName,
                    upstreamModel: modelName,
                    providerDisplayName: provider.resolvedDisplayName
                )
            }

            if candidates.count == 1, let model = candidates.first {
                modelsByName[modelName] = model
            }
        }

        self.modelsByName = modelsByName
    }

    public func resolve(modelName: String) -> ResolvedModel? {
        modelsByName[modelName]
    }

    public func listModels() -> [ResolvedModel] {
        modelsByName.values.sorted { lhs, rhs in
            lhs.publicName < rhs.publicName
        }
    }
}
