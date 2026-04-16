import Foundation

public struct UpstreamModelInfo: Codable, Sendable {
    public let id: String
    public let object: String?
    public let ownedBy: String?
    enum CodingKeys: String, CodingKey {
        case id, object
        case ownedBy = "owned_by"
    }
}

private struct UpstreamModelsEnvelope: Decodable {
    let data: [UpstreamModelInfo]
}

public actor ModelFetcher {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }

    public func fetchModels(from provider: ProviderConfig) async throws -> [UpstreamModelInfo] {
        let urlStr = provider.normalizedBaseURL + "/v1/models"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(provider.resolvedAPIKey)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(UpstreamModelsEnvelope.self, from: data).data
    }
}
