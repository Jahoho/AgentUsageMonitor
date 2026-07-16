import AgentUsageCore
import Foundation

protocol CodexRateLimitSnapshotFetching: Sendable {
    func fetchSnapshot() async throws -> CodexRateLimitSnapshot
}

struct CodexUsageAPIClient: CodexRateLimitSnapshotFetching, @unchecked Sendable {
    static let defaultUsageTimeoutSeconds: TimeInterval = 8
    static let defaultResetCreditsTimeoutSeconds: TimeInterval = 4

    private static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")
    private static let resetCreditsURL = URL(
        string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits"
    )

    private let authStore: CodexAuthStore
    private let session: URLSession?
    private let resetCreditsTimeoutSeconds: TimeInterval

    init(
        authStore: CodexAuthStore = CodexAuthStore(),
        session: URLSession? = nil,
        resetCreditsTimeoutSeconds: TimeInterval = Self.defaultResetCreditsTimeoutSeconds
    ) {
        self.authStore = authStore
        self.session = session
        self.resetCreditsTimeoutSeconds = resetCreditsTimeoutSeconds
    }

    func fetchSnapshot() async throws -> CodexRateLimitSnapshot {
        let requestSession = session ?? Self.makeEphemeralSession()
        let ownsRequestSession = session == nil
        defer {
            if ownsRequestSession {
                requestSession.finishTasksAndInvalidate()
            }
        }

        let credentials = try authStore.loadCredentials()
        guard let url = Self.usageURL else {
            throw CodexUsageAPIError.invalidURL
        }
        async let supplementalResetBank = fetchResetBankIfAvailable(
            credentials: credentials,
            session: requestSession
        )

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: Self.defaultUsageTimeoutSeconds
        )
        request.httpMethod = "GET"
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await requestSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw CodexUsageAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw CodexUsageAPIError.httpStatus(httpResponse.statusCode)
        }

        let parsedSnapshot: CodexRateLimitSnapshot
        do {
            parsedSnapshot = try CodexUsageAPIParser.parseSnapshot(
                from: data,
                email: credentials.email,
                accountPlan: credentials.plan
            )
        } catch is CodexUsageAPIParsingError {
            throw CodexUsageAPIError.missingRateLimit
        }
        let resetBank = try await supplementalResetBank ?? parsedSnapshot.resetBank

        return CodexRateLimitSnapshot(
            primary: parsedSnapshot.primary,
            secondary: parsedSnapshot.secondary,
            source: parsedSnapshot.source,
            email: parsedSnapshot.email,
            plan: parsedSnapshot.plan,
            accountPlan: parsedSnapshot.accountPlan,
            quotaPlan: parsedSnapshot.quotaPlan,
            limitName: parsedSnapshot.limitName,
            resetBank: resetBank,
            updatedAt: parsedSnapshot.updatedAt
        )
    }

    private func fetchResetBankIfAvailable(
        credentials: CodexOAuthCredentials,
        session: URLSession
    ) async throws -> CodexResetBank? {
        guard let url = Self.resetCreditsURL else {
            return nil
        }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: resetCreditsTimeoutSeconds
        )
        request.httpMethod = "GET"
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("codex-1", forHTTPHeaderField: "OpenAI-Beta")
        request.setValue("Codex Desktop", forHTTPHeaderField: "originator")
        if let accountID = credentials.accountID {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-ID")
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200..<300).contains(httpResponse.statusCode),
                  let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let availableCount = flexibleInt(
                      object["available_count"] ?? object["availableCount"]
                  ),
                  availableCount >= 0
            else {
                return nil
            }

            return CodexResetParser.resetBank(
                in: object,
                source: "OAuth API",
                updatedAt: Date()
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled || (error as? URLError)?.code == .cancelled {
                throw CancellationError()
            }
            return nil
        }
    }

    private static func makeEphemeralSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

}

enum CodexUsageAPIError: LocalizedError {
    case authMissing
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case missingRateLimit

    var errorDescription: String? {
        switch self {
        case .authMissing:
            return "Codex OAuth credentials were not found."
        case .invalidURL:
            return "Codex usage API URL is invalid."
        case .invalidResponse:
            return "Codex usage API returned a non-HTTP response."
        case .httpStatus(let status):
            return "Codex usage API returned HTTP \(status)."
        case .missingRateLimit:
            return "Codex usage API response did not include rate limit windows."
        }
    }

    var isTransient: Bool {
        switch self {
        case .httpStatus(let status):
            return status == 408 || status == 429 || (500..<600).contains(status)
        case .authMissing, .invalidURL, .invalidResponse, .missingRateLimit:
            return false
        }
    }
}

extension URLError {
    var isTransientCodexSourceFailure: Bool {
        switch code {
        case .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .notConnectedToInternet,
             .resourceUnavailable,
             .secureConnectionFailed,
             .cannotLoadFromNetwork:
            return true
        default:
            return false
        }
    }
}

private func flexibleInt(_ value: Any?) -> Int? {
    if let value = value as? Int { return value }
    if let value = value as? Double { return Int(value) }
    if let value = value as? NSNumber { return value.intValue }
    if let value = value as? String { return Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
    return nil
}
