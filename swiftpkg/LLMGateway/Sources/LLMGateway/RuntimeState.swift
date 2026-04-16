import Foundation

// MARK: - 运行时模型绑定

public struct ModelBinding: Equatable, Sendable {
    public let provider: String
    public let upstreamModel: String

    public init(provider: String, upstreamModel: String) {
        self.provider = provider
        self.upstreamModel = upstreamModel
    }
}

// MARK: - 运行时状态

public struct GatewayRuntimeState: Equatable, Sendable {
    public var activeBindings: [String: ModelBinding]
    public var lastModelRefreshAt: Date?

    public init(
        activeBindings: [String: ModelBinding] = [:],
        lastModelRefreshAt: Date? = nil
    ) {
        self.activeBindings = activeBindings
        self.lastModelRefreshAt = lastModelRefreshAt
    }

    public static func bootstrap(from config: GatewayConfig) -> GatewayRuntimeState {
        var bindings: [String: ModelBinding] = [:]

        for (publicModel, route) in config.models {
            guard let parsed = GatewayConfig.parseModelRoute(route),
                let provider = config.provider(named: parsed.provider),
                !provider.disabled
            else { continue }

            let upstreamModel = parsed.upstreamModel ?? publicModel

            if let alias = provider.aliases?[publicModel] {
                bindings[publicModel] = ModelBinding(
                    provider: provider.name, upstreamModel: alias.targetModel)
            } else if provider.models?[upstreamModel] != nil {
                bindings[publicModel] = ModelBinding(
                    provider: provider.name, upstreamModel: upstreamModel)
            }
        }

        // 支持 provider/model 格式的直接路由
        for provider in config.enabledProviders {
            for modelID in provider.publicModelIDs {
                let key = "\(provider.name)/\(modelID)"
                guard bindings[key] == nil else { continue }
                bindings[key] = ModelBinding(provider: provider.name, upstreamModel: modelID)
            }
        }

        return GatewayRuntimeState(activeBindings: bindings)
    }

    public mutating func switchBinding(model: String, to provider: String, upstreamModel: String) {
        activeBindings[model] = ModelBinding(provider: provider, upstreamModel: upstreamModel)
    }

    public mutating func removeBinding(for model: String) {
        activeBindings.removeValue(forKey: model)
    }

    public func binding(for model: String) -> ModelBinding? {
        activeBindings[model]
    }

    /// 仅路由模型
    public var publicModels: [String] {
        activeBindings.keys.sorted()
    }

    /// /v1/models 暴露的全部模型：路由模型 + 启用 provider 的 {provider}/{model}
    public func allExposedModels(config: GatewayConfig) -> [String] {
        var models = Set(activeBindings.keys)
        for provider in config.enabledProviders {
            for modelID in provider.publicModelIDs {
                models.insert("\(provider.name)/\(modelID)")
            }
        }
        return models.sorted()
    }
}
