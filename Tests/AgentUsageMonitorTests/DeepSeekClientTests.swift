import Foundation
import Testing
@testable import AgentUsageMonitor

@Test func deepSeekClientIncludesProviderErrorMessageFromHTTPBody() async throws {
    let response = HTTPURLResponse(
        url: URL(string: "https://api.deepseek.com/user/balance")!,
        statusCode: 401,
        httpVersion: nil,
        headerFields: nil
    )!
    let client = DeepSeekClient(
        apiKey: "sk-secret",
        dataFetcher: TestHTTPDataFetcher(
            data: Data("""
            {
              "error": {
                "message": "Authentication Fails, Your api key is invalid"
              }
            }
            """.utf8),
            response: response
        )
    )

    do {
        _ = try await client.fetchBalance()
        Issue.record("Expected DeepSeekClient to throw an HTTP error.")
    } catch {
        #expect(error.localizedDescription.contains("HTTP 401"))
        #expect(error.localizedDescription.contains("Authentication Fails"))
        #expect(error.localizedDescription.contains("sk-secret") == false)
    }
}

@Test func deepSeekClientUsesFallbackHTTPStatusWhenErrorBodyHasNoMessage() async throws {
    let response = HTTPURLResponse(
        url: URL(string: "https://api.deepseek.com/user/balance")!,
        statusCode: 429,
        httpVersion: nil,
        headerFields: nil
    )!
    let client = DeepSeekClient(
        apiKey: "sk-secret",
        dataFetcher: TestHTTPDataFetcher(data: Data("{}".utf8), response: response)
    )

    do {
        _ = try await client.fetchBalance()
        Issue.record("Expected DeepSeekClient to throw an HTTP error.")
    } catch {
        #expect(error.localizedDescription == "DeepSeek returned HTTP 429.")
        #expect(error.localizedDescription.contains("sk-secret") == false)
    }
}

private struct TestHTTPDataFetcher: HTTPDataFetching {
    let data: Data
    let response: URLResponse

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true)
        return (data, response)
    }
}
