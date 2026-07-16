import AgentUsageCore
import Foundation

protocol DeepSeekBalanceFetching: Sendable {
    func fetchBalance(apiKey: String) async throws -> DeepSeekBalanceResponse
}

struct DeepSeekBalanceClient: DeepSeekBalanceFetching {
    func fetchBalance(apiKey: String) async throws -> DeepSeekBalanceResponse {
        try await DeepSeekClient(apiKey: apiKey).fetchBalance()
    }
}

struct DeepSeekClient {
    let apiKey: String
    var endpoint = URL(string: "https://api.deepseek.com/user/balance")!
    var dataFetcher: any HTTPDataFetching = URLSession.shared

    func fetchBalance() async throws -> DeepSeekBalanceResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await dataFetcher.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw DeepSeekClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw DeepSeekClientError.httpStatus(
                httpResponse.statusCode,
                providerMessage(from: data, apiKey: apiKey)
            )
        }

        return try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: data)
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

enum DeepSeekClientError: LocalizedError {
    case invalidResponse
    case httpStatus(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "DeepSeek returned a non-HTTP response."
        case .httpStatus(let status, let message):
            if let message {
                return "DeepSeek returned HTTP \(status): \(message)"
            }
            return "DeepSeek returned HTTP \(status)."
        }
    }
}
