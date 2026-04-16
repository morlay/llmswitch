import Foundation

private struct UpstreamModelsEnvelope: Decodable {
    let data: [ProviderModel]
}

public struct ProviderClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchModels(for provider: ProviderConfig) async throws -> [ProviderModel] {
        let modelsURL = buildModelsURL(baseURL: provider.baseURL)

        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(provider.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8 body>"
            throw NSError(
                domain: "LLMSwitch.ProviderClient",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "Provider \(provider.name) returned \(httpResponse.statusCode): \(body)"]
            )
        }

        let envelope = try JSONDecoder().decode(UpstreamModelsEnvelope.self, from: data)
        return envelope.data
    }

    private func buildModelsURL(baseURL: URL) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, "v1", "models"]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        return components.url ?? baseURL.appending(path: "v1/models")
    }
}
