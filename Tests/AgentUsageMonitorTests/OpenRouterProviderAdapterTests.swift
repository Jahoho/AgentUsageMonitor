import AgentUsageCore
import Foundation
import Testing
@testable import AgentUsageMonitor

@Test func openRouterProviderAdapterRequiresAPIKey() async {
    let adapter = OpenRouterProviderAdapter(
        credentialStore: OpenRouterTestCredentialStore(apiKey: nil),
        usageClient: OpenRouterTestUsageClient(result: .success(openRouterFetchResult()))
    )

    let snapshot = await adapter.snapshot()

    #expect(snapshot.health == .needsSetup)
    #expect(snapshot.id == "openrouter")
    #expect(snapshot.sourceDiagnostics?.first?.status == .notAttempted)
}

@Test func openRouterProviderAdapterReturnsOnlyOfficialUsage() async {
    let adapter = OpenRouterProviderAdapter(
        credentialStore: OpenRouterTestCredentialStore(apiKey: "sk-or-v1-test"),
        usageClient: OpenRouterTestUsageClient(result: .success(openRouterFetchResult()))
    )

    let snapshot = await adapter.snapshot()

    #expect(snapshot.health == .ready)
    #expect(snapshot.metrics.first { $0.id == "month-cost" }?.value == "$3.00")
    #expect(snapshot.metrics.first { $0.id == "month-cost" }?.confidence == .official)
    #expect(snapshot.accounts?.first?.metrics.first { $0.id == "account" }?.confidence == .observed)
    #expect(snapshot.activity == nil)
    #expect(snapshot.sourceDiagnostics?.first?.status == .success)
}

@Test func openRouterProviderAdapterReportsCurrentFailureWithoutLeakingKey() async {
    let apiKey = "sk-or-v1-secret"
    let adapter = OpenRouterProviderAdapter(
        credentialStore: OpenRouterTestCredentialStore(apiKey: apiKey),
        usageClient: OpenRouterTestUsageClient(
            result: .failure(OpenRouterAdapterTestError.failed("Rejected \(apiKey)"))
        )
    )

    let snapshot = await adapter.snapshot()

    #expect(snapshot.health == .error)
    #expect(snapshot.metrics.first { $0.id == "source" }?.detail.contains(apiKey) == false)
    #expect(snapshot.metrics.first { $0.id == "source" }?.detail.contains("[redacted]") == true)
    #expect(snapshot.bars.isEmpty)
    #expect(snapshot.activity == nil)
}

@Test func openRouterProviderAdapterLoadsOfficialManagedKeyNamesAndModelActivity() async throws {
    let managementCredential = OpenRouterCredential(
        id: "management",
        label: "Admin",
        isDefault: true,
        createdAt: Date(timeIntervalSince1970: 0)
    )
    let store = OpenRouterMultiTestCredentialStore(
        resolved: [
            OpenRouterResolvedCredential(
                credential: managementCredential,
                apiKey: "sk-or-v1-management"
            )
        ]
    )
    let client = OpenRouterManagementUsageClient()
    let adapter = OpenRouterProviderAdapter(credentialStore: store, usageClient: client)

    let snapshot = await adapter.snapshot()

    #expect(snapshot.health == .ready)
    #expect(snapshot.accounts?.count == 2)
    let account = try #require(snapshot.accounts?.first { $0.id == "managed-hash-1" })
    #expect(account.name == "Production")
    #expect(account.detail.contains("Official management key catalog"))
    #expect(account.metrics.first { $0.id == "source" }?.detail.contains("/api/v1/keys") == true)
    #expect(account.activity?.first?.value == 300)
    #expect(account.activity?.first?.confidence == .official)

    let model = try #require(account.models.first)
    #expect(model.model == "openai/gpt-4.1")
    #expect(model.requestCount == 2)
    #expect(model.totalTokens == 300)
    #expect(model.spendUSD == 0.03)
    #expect(model.confidence == .official)
    #expect(await client.requestedHashes() == ["hash-1"])
}

@Test func openRouterProviderAdapterKeepsSuccessfulOfficialKeyWhenAnotherKeyFails() async throws {
    let first = OpenRouterResolvedCredential(
        credential: OpenRouterCredential(
            id: "good",
            label: "Production",
            isDefault: true,
            createdAt: Date(timeIntervalSince1970: 0)
        ),
        apiKey: "sk-or-v1-good"
    )
    let second = OpenRouterResolvedCredential(
        credential: OpenRouterCredential(
            id: "bad",
            label: "Expired",
            isDefault: false,
            createdAt: Date(timeIntervalSince1970: 1)
        ),
        apiKey: "sk-or-v1-bad"
    )
    let store = OpenRouterMultiTestCredentialStore(resolved: [first, second])
    let adapter = OpenRouterProviderAdapter(
        credentialStore: store,
        usageClient: OpenRouterPartialFailureUsageClient(failingAPIKey: second.apiKey)
    )

    let snapshot = await adapter.snapshot()

    #expect(snapshot.health == .ready)
    let ready = try #require(snapshot.accounts?.first { $0.id == "saved-good" })
    let failed = try #require(snapshot.accounts?.first { $0.id == "saved-bad" })
    #expect(ready.health == .ready)
    #expect(ready.metrics.first { $0.id == "month-cost" }?.confidence == .official)
    #expect(failed.health == .error)
    #expect(failed.metrics.first?.confidence == .unavailable)
    #expect(failed.metrics.first?.detail.contains(second.apiKey) == false)
    #expect(failed.metrics.first?.detail.contains("[redacted]") == true)
    let diagnostic = snapshot.sourceDiagnostics?.first
    #expect(diagnostic?.status == .partial)
    #expect(diagnostic?.lastSuccessAt != nil)
    #expect(diagnostic?.lastFailureAt != nil)
}

@Test func openRouterProviderAdapterIsolatesOneKeychainReadFailure() async throws {
    let store = OpenRouterPartiallyUnreadableCredentialStore()
    let adapter = OpenRouterProviderAdapter(
        credentialStore: store,
        usageClient: OpenRouterTestUsageClient(result: .success(openRouterFetchResult()))
    )

    let snapshot = await adapter.snapshot()

    #expect(snapshot.health == .ready)
    #expect(snapshot.accounts?.first { $0.id == "saved-readable" }?.health == .ready)
    #expect(snapshot.accounts?.first { $0.id == "saved-unreadable" }?.health == .error)
}

@Test func openRouterProviderAdapterKeepsManagedKeyUsageWhenOfficialActivityFails() async throws {
    let managementCredential = OpenRouterCredential(
        id: "management",
        label: "Admin",
        isDefault: true,
        createdAt: Date(timeIntervalSince1970: 0)
    )
    let store = OpenRouterMultiTestCredentialStore(
        resolved: [
            OpenRouterResolvedCredential(
                credential: managementCredential,
                apiKey: "sk-or-v1-management"
            )
        ]
    )
    let adapter = OpenRouterProviderAdapter(
        credentialStore: store,
        usageClient: OpenRouterFailingActivityUsageClient()
    )

    let snapshot = await adapter.snapshot()

    #expect(snapshot.health == .ready)
    let managed = try #require(snapshot.accounts?.first { $0.id == "managed-hash-1" })
    #expect(managed.health == .ready)
    #expect(managed.metrics.first { $0.id == "month-cost" }?.confidence == .official)
    #expect(managed.models.isEmpty)
    #expect(managed.activity == nil)
    #expect(managed.notes.contains { $0.contains("activity sync failed") })
}

private struct OpenRouterTestCredentialStore: OpenRouterCredentialStoring {
    let storedAPIKey: String?

    init(apiKey: String?) {
        storedAPIKey = apiKey
    }

    func credentials() throws -> [OpenRouterCredential] {
        storedAPIKey == nil ? [] : [credential]
    }

    func addCredential(label: String, apiKey: String) throws -> OpenRouterCredential { credential }
    func deleteCredential(id: String) throws {}
    func setDefaultCredential(id: String) throws {}
    func readSecret(for id: String) throws -> String? { storedAPIKey }
    func resolvedCredentials() throws -> [OpenRouterResolvedCredential] {
        guard let storedAPIKey else { return [] }
        return [OpenRouterResolvedCredential(credential: credential, apiKey: storedAPIKey)]
    }
    func defaultResolvedCredential() throws -> OpenRouterResolvedCredential? {
        try resolvedCredentials().first
    }

    private var credential: OpenRouterCredential {
        OpenRouterCredential(
            id: "test-key",
            label: "Test",
            isDefault: true,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }
}

private struct OpenRouterTestUsageClient: OpenRouterUsageFetching {
    let result: Result<OpenRouterUsageFetchResult, Error>

    func fetchUsage(apiKey: String) async throws -> OpenRouterUsageFetchResult {
        try result.get()
    }

    func fetchManagedKeys(apiKey: String) async throws -> [OpenRouterManagedKeyInfo] {
        throw OpenRouterAdapterTestError.failed("Unexpected managed keys request")
    }

    func fetchActivity(apiKey: String, keyHash: String) async throws -> [OpenRouterActivityItem] {
        throw OpenRouterAdapterTestError.failed("Unexpected activity request")
    }
}

private struct OpenRouterMultiTestCredentialStore: OpenRouterCredentialStoring {
    let resolved: [OpenRouterResolvedCredential]

    func credentials() throws -> [OpenRouterCredential] { resolved.map(\.credential) }
    func addCredential(label: String, apiKey: String) throws -> OpenRouterCredential {
        throw OpenRouterAdapterTestError.failed("Unsupported")
    }
    func deleteCredential(id: String) throws {}
    func setDefaultCredential(id: String) throws {}
    func readSecret(for id: String) throws -> String? {
        resolved.first { $0.credential.id == id }?.apiKey
    }
    func resolvedCredentials() throws -> [OpenRouterResolvedCredential] { resolved }
    func defaultResolvedCredential() throws -> OpenRouterResolvedCredential? {
        resolved.first { $0.credential.isDefault } ?? resolved.first
    }
}

private actor OpenRouterManagementUsageClient: OpenRouterUsageFetching {
    private var hashes: [String] = []

    func fetchUsage(apiKey: String) async throws -> OpenRouterUsageFetchResult {
        OpenRouterUsageFetchResult(
            usage: OpenRouterOfficialUsage(
                key: OpenRouterKeyInfo(
                    label: "management-key",
                    usage: 0,
                    usageDaily: 0,
                    usageWeekly: 0,
                    usageMonthly: 0,
                    isManagementKey: true
                ),
                credits: OpenRouterCreditsInfo(totalCredits: 100, totalUsage: 25)
            ),
            notes: []
        )
    }

    func fetchManagedKeys(apiKey: String) async throws -> [OpenRouterManagedKeyInfo] {
        [
            OpenRouterManagedKeyInfo(
                hash: "hash-1",
                name: "Production",
                label: "Production API Key",
                disabled: false,
                usage: 10,
                usageDaily: 1,
                usageWeekly: 5,
                usageMonthly: 10
            )
        ]
    }

    func fetchActivity(apiKey: String, keyHash: String) async throws -> [OpenRouterActivityItem] {
        hashes.append(keyHash)
        return [
            OpenRouterActivityItem(
                date: "2026-07-13",
                model: "openai/gpt-4.1",
                modelPermaslug: "openai/gpt-4.1-2025-04-14",
                providerName: "OpenAI",
                requests: 2,
                promptTokens: 100,
                completionTokens: 200,
                reasoningTokens: 50,
                usage: 0.03
            )
        ]
    }

    func requestedHashes() -> [String] { hashes }
}

private struct OpenRouterPartialFailureUsageClient: OpenRouterUsageFetching {
    let failingAPIKey: String

    func fetchUsage(apiKey: String) async throws -> OpenRouterUsageFetchResult {
        if apiKey == failingAPIKey {
            throw OpenRouterAdapterTestError.failed("Rejected \(apiKey)")
        }
        return openRouterFetchResult()
    }

    func fetchManagedKeys(apiKey: String) async throws -> [OpenRouterManagedKeyInfo] {
        throw OpenRouterAdapterTestError.failed("Unexpected managed keys request")
    }

    func fetchActivity(apiKey: String, keyHash: String) async throws -> [OpenRouterActivityItem] {
        throw OpenRouterAdapterTestError.failed("Unexpected activity request")
    }
}

private struct OpenRouterPartiallyUnreadableCredentialStore: OpenRouterCredentialStoring {
    private let readable = OpenRouterCredential(
        id: "readable",
        label: "Readable",
        isDefault: true,
        createdAt: Date(timeIntervalSince1970: 0)
    )
    private let unreadable = OpenRouterCredential(
        id: "unreadable",
        label: "Unreadable",
        isDefault: false,
        createdAt: Date(timeIntervalSince1970: 1)
    )

    func credentials() throws -> [OpenRouterCredential] { [readable, unreadable] }
    func addCredential(label: String, apiKey: String) throws -> OpenRouterCredential {
        throw OpenRouterAdapterTestError.failed("Unsupported")
    }
    func deleteCredential(id: String) throws {}
    func setDefaultCredential(id: String) throws {}
    func readSecret(for id: String) throws -> String? {
        if id == unreadable.id {
            throw OpenRouterAdapterTestError.failed("Keychain denied access")
        }
        return "sk-or-v1-readable"
    }
    func resolvedCredentials() throws -> [OpenRouterResolvedCredential] {
        throw OpenRouterAdapterTestError.failed("Adapter should isolate reads directly")
    }
    func defaultResolvedCredential() throws -> OpenRouterResolvedCredential? { nil }
}

private struct OpenRouterFailingActivityUsageClient: OpenRouterUsageFetching {
    func fetchUsage(apiKey: String) async throws -> OpenRouterUsageFetchResult {
        OpenRouterUsageFetchResult(
            usage: OpenRouterOfficialUsage(
                key: OpenRouterKeyInfo(
                    label: "management-key",
                    usage: 0,
                    usageDaily: 0,
                    usageWeekly: 0,
                    usageMonthly: 0,
                    isManagementKey: true
                )
            ),
            notes: []
        )
    }

    func fetchManagedKeys(apiKey: String) async throws -> [OpenRouterManagedKeyInfo] {
        [
            OpenRouterManagedKeyInfo(
                hash: "hash-1",
                name: "Production",
                disabled: false,
                usage: 10,
                usageDaily: 1,
                usageWeekly: 5,
                usageMonthly: 10
            )
        ]
    }

    func fetchActivity(apiKey: String, keyHash: String) async throws -> [OpenRouterActivityItem] {
        throw OpenRouterAdapterTestError.failed("HTTP 503")
    }
}

private func openRouterFetchResult() -> OpenRouterUsageFetchResult {
    OpenRouterUsageFetchResult(
        usage: OpenRouterOfficialUsage(
            key: OpenRouterKeyInfo(
                label: "test-key",
                usage: 4,
                usageDaily: 0.5,
                usageWeekly: 2,
                usageMonthly: 3
            )
        ),
        notes: []
    )
}

private enum OpenRouterAdapterTestError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message):
            return message
        }
    }
}
