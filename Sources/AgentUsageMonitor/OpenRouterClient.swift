import AgentUsageCore
import Foundation

struct OpenRouterUsageFetchResult: Equatable, Sendable {
    let usage: OpenRouterOfficialUsage
    let notes: [String]
}

protocol OpenRouterUsageFetching: Sendable {
    func fetchUsage(apiKey: String) async throws -> OpenRouterUsageFetchResult
    func fetchManagedKeys(apiKey: String) async throws -> [OpenRouterManagedKeyInfo]
    func fetchActivity(apiKey: String, keyHash: String) async throws -> [OpenRouterActivityItem]
}

struct OpenRouterUsageClient: OpenRouterUsageFetching {
    var keyEndpoint = URL(string: "https://openrouter.ai/api/v1/key")!
    var creditsEndpoint = URL(string: "https://openrouter.ai/api/v1/credits")!
    var keysEndpoint = URL(string: "https://openrouter.ai/api/v1/keys")!
    var activityEndpoint = URL(string: "https://openrouter.ai/api/v1/activity")!
    var dataFetcher: any HTTPDataFetching = URLSession.shared
    var timeoutInterval: TimeInterval = 10

    func fetchUsage(apiKey: String) async throws -> OpenRouterUsageFetchResult {
        let keyResponse: OpenRouterKeyResponse = try await fetch(
            OpenRouterKeyResponse.self,
            from: keyEndpoint,
            apiKey: apiKey
        )

        var credits: OpenRouterCreditsInfo?
        var notes: [String] = []

        // OpenRouter only allows management keys to call the account credits endpoint.
        if keyResponse.data.isManagementKey == true {
            do {
                let response: OpenRouterCreditsResponse = try await fetch(
                    OpenRouterCreditsResponse.self,
                    from: creditsEndpoint,
                    apiKey: apiKey
                )
                credits = response.data
            } catch {
                if Task.isCancelled {
                    throw CancellationError()
                }
                notes.append("Official account credits sync failed: \(error.localizedDescription)")
            }
        }

        return OpenRouterUsageFetchResult(
            usage: OpenRouterOfficialUsage(key: keyResponse.data, credits: credits),
            notes: notes
        )
    }

    func fetchManagedKeys(apiKey: String) async throws -> [OpenRouterManagedKeyInfo] {
        var keys: [OpenRouterManagedKeyInfo] = []
        var seenHashes = Set<String>()
        var offset = 0

        for _ in 0..<100 {
            let endpoint = try endpoint(
                keysEndpoint,
                queryItems: [
                    URLQueryItem(name: "include_disabled", value: "true"),
                    URLQueryItem(name: "offset", value: String(offset))
                ]
            )
            let response: OpenRouterKeysResponse = try await fetch(
                OpenRouterKeysResponse.self,
                from: endpoint,
                apiKey: apiKey
            )

            guard response.data.isEmpty == false else {
                return keys
            }

            for key in response.data {
                guard seenHashes.insert(key.hash).inserted else {
                    throw OpenRouterClientError.paginationDidNotAdvance
                }
                keys.append(key)
            }
            offset += response.data.count
        }

        throw OpenRouterClientError.paginationLimitReached
    }

    func fetchActivity(apiKey: String, keyHash: String) async throws -> [OpenRouterActivityItem] {
        let endpoint = try endpoint(
            activityEndpoint,
            queryItems: [URLQueryItem(name: "api_key_hash", value: keyHash)]
        )
        let response: OpenRouterActivityResponse = try await fetch(
            OpenRouterActivityResponse.self,
            from: endpoint,
            apiKey: apiKey
        )
        return response.data
    }

    private func fetch<Response: Decodable>(
        _ type: Response.Type,
        from endpoint: URL,
        apiKey: String
    ) async throws -> Response {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutInterval
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await dataFetcher.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw OpenRouterClientError.httpStatus(
                httpResponse.statusCode,
                providerMessage(from: data, apiKey: apiKey)
            )
        }

        return try JSONDecoder().decode(type, from: data)
    }

    private func endpoint(_ baseURL: URL, queryItems: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw OpenRouterClientError.invalidEndpoint
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw OpenRouterClientError.invalidEndpoint
        }
        return url
    }

    private func providerMessage(from data: Data, apiKey: String) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let message = stringValue(in: object)
        else {
            return nil
        }

        return message.replacingOccurrences(of: apiKey, with: "[redacted]")
    }

    private func stringValue(in value: Any) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let object = value as? [String: Any] {
            for key in ["message", "detail", "error_description"] {
                if let message = object[key].flatMap(stringValue) {
                    return message
                }
            }
            if let message = object["error"].flatMap(stringValue) {
                return message
            }
        }

        return nil
    }
}

enum OpenRouterClientError: LocalizedError {
    case invalidResponse
    case invalidEndpoint
    case httpStatus(Int, String?)
    case paginationDidNotAdvance
    case paginationLimitReached

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "OpenRouter returned a non-HTTP response."
        case .invalidEndpoint:
            return "OpenRouter request URL could not be created."
        case .httpStatus(let status, let message):
            if let message {
                return "OpenRouter returned HTTP \(status): \(message)"
            }
            return "OpenRouter returned HTTP \(status)."
        case .paginationDidNotAdvance:
            return "OpenRouter API key pagination repeated a previous key."
        case .paginationLimitReached:
            return "OpenRouter API key pagination exceeded the safety limit."
        }
    }
}
