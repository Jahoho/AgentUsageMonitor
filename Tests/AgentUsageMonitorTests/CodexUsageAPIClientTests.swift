import AgentUsageCore
import Foundation
import Testing
@testable import AgentUsageMonitor

@Suite(.serialized)
struct CodexUsageAPIClientTests {
    @Test func fetchesOfficialResetCreditExpiryAlongsideUsage() async throws {
        CodexUsageURLProtocolStub.reset(mode: .resetSuccess)
        let harness = try makeHarness()
        defer { harness.cleanUp() }

        let snapshot = try await harness.client.fetchSnapshot()
        let bank = try #require(snapshot.resetBank)
        let entry = try #require(bank.entries.first)
        let requests = CodexUsageURLProtocolStub.recordedRequests()

        #expect(snapshot.primary?.usedPercent == 25)
        #expect(bank.availableCount(now: snapshot.updatedAt) == 2)
        #expect(entry.label == "One free rate limit reset")
        #expect(entry.expiresAt == ISO8601DateFormatter().date(from: "2030-03-17T00:00:00Z"))
        let requestPaths = requests.map { $0.url?.path }.compactMap { $0 }
        #expect(requestPaths.count == 2)
        #expect(Set(requestPaths) == Set([
            "/backend-api/wham/usage",
            "/backend-api/wham/rate-limit-reset-credits"
        ]))

        let resetRequest = try #require(
            requests.first { $0.url?.path.hasSuffix("/rate-limit-reset-credits") == true }
        )
        let usageRequest = try #require(
            requests.first { $0.url?.path.hasSuffix("/usage") == true }
        )
        #expect(usageRequest.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(resetRequest.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")
        #expect(resetRequest.value(forHTTPHeaderField: "ChatGPT-Account-ID") == "account-123")
        #expect(resetRequest.value(forHTTPHeaderField: "OpenAI-Beta") == "codex-1")
        #expect(resetRequest.value(forHTTPHeaderField: "originator") == "Codex Desktop")
        #expect(resetRequest.timeoutInterval == 4)
    }

    @Test func resetCreditFailureDoesNotDiscardOfficialUsage() async throws {
        CodexUsageURLProtocolStub.reset(mode: .resetFailure)
        let harness = try makeHarness()
        defer { harness.cleanUp() }

        let snapshot = try await harness.client.fetchSnapshot()
        let requestPaths = CodexUsageURLProtocolStub.recordedRequests()
            .compactMap { $0.url?.path }

        #expect(snapshot.primary?.usedPercent == 25)
        #expect(snapshot.resetBank?.reportedAvailableCount == 1)
        #expect(snapshot.resetBank?.entries.first?.id == "embedded-reset")
        #expect(requestPaths.count == 2)
        #expect(Set(requestPaths) == Set([
            "/backend-api/wham/usage",
            "/backend-api/wham/rate-limit-reset-credits"
        ]))
    }

    private func makeHarness() throws -> CodexUsageAPIClientHarness {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentUsageMonitor-CodexUsageAPIClientTests-(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let authData = try JSONSerialization.data(withJSONObject: [
            "tokens": [
                "access_token": "test-token",
                "account_id": "account-123"
            ]
        ])
        try authData.write(to: directory.appendingPathComponent("auth.json"))

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CodexUsageURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        let authStore = CodexAuthStore(
            fileManager: .default,
            environment: ["CODEX_HOME": directory.path]
        )

        return CodexUsageAPIClientHarness(
            client: CodexUsageAPIClient(authStore: authStore, session: session),
            session: session,
            directory: directory
        )
    }
}

private struct CodexUsageAPIClientHarness {
    let client: CodexUsageAPIClient
    let session: URLSession
    let directory: URL

    func cleanUp() {
        session.invalidateAndCancel()
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class CodexUsageURLProtocolStub: URLProtocol, @unchecked Sendable {
    enum Mode {
        case resetSuccess
        case resetFailure
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var mode: Mode = .resetSuccess
    nonisolated(unsafe) private static var requests: [URLRequest] = []

    static func reset(mode: Mode) {
        lock.lock()
        self.mode = mode
        requests = []
        lock.unlock()
    }

    static func recordedRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "chatgpt.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let mode: Mode
        Self.lock.lock()
        Self.requests.append(request)
        mode = Self.mode
        Self.lock.unlock()

        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let statusCode: Int
        let data: Data
        switch url.path {
        case "/backend-api/wham/usage":
            statusCode = 200
            data = Data(Self.usageJSON.utf8)
        case "/backend-api/wham/rate-limit-reset-credits":
            statusCode = mode == .resetSuccess ? 200 : 500
            data = mode == .resetSuccess ? Data(Self.resetCreditsJSON.utf8) : Data("server error".utf8)
        default:
            statusCode = 404
            data = Data()
        }

        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static let usageJSON = """
    {
      "plan_type": "pro",
      "rate_limit": {
        "primary_window": {
          "used_percent": 25,
          "limit_window_seconds": 18000,
          "reset_at": 1900000000
        }
      },
      "rate_limit_reset_credits": {
        "available_count": 1,
        "credits": [
          {
            "id": "embedded-reset",
            "status": "available",
            "expires_at": "2031-03-17T00:00:00Z"
          }
        ]
      }
    }
    """

    private static let resetCreditsJSON = """
    {
      "credits": [
        {
          "id": "RateLimitResetCredit_api",
          "reset_type": "codex_rate_limits",
          "status": "available",
          "granted_at": "2030-02-15T00:00:00Z",
          "expires_at": "2030-03-17T00:00:00Z",
          "title": "One free rate limit reset",
          "description": "Thanks for using Codex!"
        }
      ],
      "available_count": 2
    }
    """
}
