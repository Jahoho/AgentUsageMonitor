import AgentUsageCore
import Foundation
import Testing
@testable import AgentUsageMonitor

@Test func openRouterClientUsesOnlyCurrentKeyEndpointForStandardKey() async throws {
    let fetcher = OpenRouterHTTPStub(
        responses: [
            "/api/v1/key": .json(openRouterKeyJSON(isManagementKey: false))
        ]
    )
    let client = OpenRouterUsageClient(dataFetcher: fetcher)

    let result = try await client.fetchUsage(apiKey: "sk-or-v1-standard")

    #expect(result.usage.key.usageMonthly == 75)
    #expect(result.usage.credits == nil)
    #expect(await fetcher.requestPaths() == ["/api/v1/key"])
}

@Test func openRouterClientAddsCreditsOnlyForManagementKey() async throws {
    let fetcher = OpenRouterHTTPStub(
        responses: [
            "/api/v1/key": .json(openRouterKeyJSON(isManagementKey: true)),
            "/api/v1/credits": .json(
                Data(#"{"data":{"total_credits":250,"total_usage":80.5}}"#.utf8)
            )
        ]
    )
    let client = OpenRouterUsageClient(dataFetcher: fetcher)

    let result = try await client.fetchUsage(apiKey: "sk-or-v1-management")

    #expect(result.usage.credits == OpenRouterCreditsInfo(totalCredits: 250, totalUsage: 80.5))
    #expect(await fetcher.requestPaths() == ["/api/v1/key", "/api/v1/credits"])
}

@Test func openRouterClientKeepsOfficialKeyUsageWhenOptionalCreditsFail() async throws {
    let fetcher = OpenRouterHTTPStub(
        responses: [
            "/api/v1/key": .json(openRouterKeyJSON(isManagementKey: true)),
            "/api/v1/credits": .json(
                Data(#"{"error":{"message":"Management key required"}}"#.utf8),
                statusCode: 403
            )
        ]
    )
    let client = OpenRouterUsageClient(dataFetcher: fetcher)

    let result = try await client.fetchUsage(apiKey: "sk-or-v1-management")

    #expect(result.usage.key.usageDaily == 1.25)
    #expect(result.usage.credits == nil)
    #expect(result.notes.contains { $0.contains("HTTP 403") })
}

@Test func openRouterClientRedactsAPIKeyFromProviderError() async {
    let apiKey = "sk-or-v1-secret"
    let body = Data(#"{"error":{"code":401,"message":"Invalid key sk-or-v1-secret"}}"#.utf8)
    let fetcher = OpenRouterHTTPStub(
        responses: [
            "/api/v1/key": .json(body, statusCode: 401)
        ]
    )
    let client = OpenRouterUsageClient(dataFetcher: fetcher)

    do {
        _ = try await client.fetchUsage(apiKey: apiKey)
        Issue.record("Expected OpenRouter request to fail")
    } catch {
        #expect(error.localizedDescription.contains(apiKey) == false)
        #expect(error.localizedDescription.contains("[redacted]"))
    }
}

@Test func openRouterClientPaginatesOfficialManagedKeysByOffset() async throws {
    let fetcher = OpenRouterHTTPStub(
        responses: [
            "/api/v1/keys?include_disabled=true&offset=0": .json(openRouterManagedKeysJSON(hash: "hash-1", name: "Production")),
            "/api/v1/keys?include_disabled=true&offset=1": .json(openRouterManagedKeysJSON(hash: "hash-2", name: "Research")),
            "/api/v1/keys?include_disabled=true&offset=2": .json(Data(#"{"data":[]}"#.utf8))
        ]
    )
    let client = OpenRouterUsageClient(dataFetcher: fetcher)

    let keys = try await client.fetchManagedKeys(apiKey: "sk-or-v1-management")

    #expect(keys.map(\.hash) == ["hash-1", "hash-2"])
    #expect(keys.map(\.name) == ["Production", "Research"])
    #expect(await fetcher.requestKeys() == [
        "/api/v1/keys?include_disabled=true&offset=0",
        "/api/v1/keys?include_disabled=true&offset=1",
        "/api/v1/keys?include_disabled=true&offset=2"
    ])
}

@Test func openRouterClientFetchesActivityForExactOfficialKeyHash() async throws {
    let fetcher = OpenRouterHTTPStub(
        responses: [
            "/api/v1/activity?api_key_hash=hash-1": .json(
                Data(
                    #"{"data":[{"date":"2026-07-13","endpoint_id":"endpoint-1","model":"openai/gpt-4.1","model_permaslug":"openai/gpt-4.1-2025-04-14","provider_name":"OpenAI","requests":2,"prompt_tokens":100,"completion_tokens":200,"reasoning_tokens":50,"usage":0.03}]}"#.utf8
                )
            )
        ]
    )
    let client = OpenRouterUsageClient(dataFetcher: fetcher)

    let activity = try await client.fetchActivity(
        apiKey: "sk-or-v1-management",
        keyHash: "hash-1"
    )

    #expect(activity.first?.model == "openai/gpt-4.1")
    #expect(activity.first?.promptTokens == 100)
    #expect(await fetcher.requestKeys() == ["/api/v1/activity?api_key_hash=hash-1"])
}

private actor OpenRouterHTTPStub: HTTPDataFetching {
    struct Response: Sendable {
        let data: Data
        let statusCode: Int

        static func json(_ data: Data, statusCode: Int = 200) -> Response {
            Response(data: data, statusCode: statusCode)
        }
    }

    private let responses: [String: Response]
    private var paths: [String] = []
    private var keys: [String] = []

    init(responses: [String: Response]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let path = request.url?.path ?? ""
        let requestKey = request.url.map(Self.requestKey) ?? path
        paths.append(path)
        keys.append(requestKey)
        guard let response = responses[requestKey] ?? responses[path], let url = request.url else {
            throw OpenRouterTestError.missingStub(requestKey)
        }

        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response.data, httpResponse)
    }

    func requestPaths() -> [String] {
        paths
    }

    func requestKeys() -> [String] {
        keys
    }

    private static func requestKey(_ url: URL) -> String {
        guard let query = url.query, query.isEmpty == false else {
            return url.path
        }
        return "\(url.path)?\(query)"
    }
}

private func openRouterKeyJSON(isManagementKey: Bool) -> Data {
    Data(
        """
        {
          "data": {
            "label": "sk-or-v1-test...1234",
            "limit": 100,
            "limit_remaining": 25,
            "limit_reset": "monthly",
            "usage": 80.5,
            "usage_daily": 1.25,
            "usage_weekly": 12.5,
            "usage_monthly": 75,
            "is_management_key": \(isManagementKey)
          }
        }
        """.utf8
    )
}

private func openRouterManagedKeysJSON(hash: String, name: String) -> Data {
    Data(
        """
        {
          "data": [{
            "hash": "\(hash)",
            "name": "\(name)",
            "label": "\(name) API Key",
            "disabled": false,
            "limit": null,
            "limit_remaining": null,
            "limit_reset": null,
            "usage": 10,
            "usage_daily": 1,
            "usage_weekly": 5,
            "usage_monthly": 10
          }]
        }
        """.utf8
    )
}

private enum OpenRouterTestError: LocalizedError {
    case missingStub(String)

    var errorDescription: String? {
        switch self {
        case .missingStub(let path):
            return "Missing HTTP stub for \(path)"
        }
    }
}
