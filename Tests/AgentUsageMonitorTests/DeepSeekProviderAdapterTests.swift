import AgentUsageCore
import Foundation
import Testing
@testable import AgentUsageMonitor

@Test func deepSeekProviderAdapterReturnsSetupWithoutCredentials() async {
    let adapter = DeepSeekProviderAdapter(
        credentialStore: TestDeepSeekCredentialStore(storedCredentials: []),
        usageStore: TestUsageEventStore(),
        balanceClient: TestDeepSeekBalanceClient(result: .success(balanceResponse()))
    )

    let snapshot = await adapter.snapshot()

    #expect(snapshot.health == .needsSetup)
    #expect(snapshot.metrics.first { $0.id == "balance" }?.value == "Not configured")
    #expect(snapshot.sourceDiagnostics?.first?.status == .notAttempted)
}

@Test func deepSeekProviderAdapterReturnsOfficialBalanceForValidCredential() async {
    let credential = DeepSeekCredential(
        id: "key-1",
        label: "Primary",
        isDefault: true,
        createdAt: Date()
    )
    let adapter = DeepSeekProviderAdapter(
        credentialStore: TestDeepSeekCredentialStore(storedCredentials: [credential], secrets: ["key-1": "sk-test"]),
        usageStore: TestUsageEventStore(),
        balanceClient: TestDeepSeekBalanceClient(result: .success(balanceResponse(total: "12.50")))
    )

    let snapshot = await adapter.snapshot()

    #expect(snapshot.health == .ready)
    #expect(snapshot.metrics.first { $0.id == "balance" }?.value == "12.50 USD")
    #expect(snapshot.metrics.first { $0.id == "balance" }?.confidence == .official)
    #expect(snapshot.sourceDiagnostics?.first?.status == .success)
}

@Test func deepSeekProviderAdapterReportsAPIErrorWithoutLeakingKey() async {
    let credential = DeepSeekCredential(
        id: "key-1",
        label: "Primary",
        isDefault: true,
        createdAt: Date()
    )
    let adapter = DeepSeekProviderAdapter(
        credentialStore: TestDeepSeekCredentialStore(storedCredentials: [credential], secrets: ["key-1": "sk-secret"]),
        usageStore: TestUsageEventStore(),
        balanceClient: TestDeepSeekBalanceClient(result: .failure(TestProviderError.failed))
    )

    let snapshot = await adapter.snapshot()

    #expect(snapshot.health == .error)
    #expect(snapshot.notes.contains { $0.contains("sk-secret") } == false)
}

@Test func deepSeekProviderAdapterPassesObservedEventsIntoMatchingKeyProfile() async throws {
    let credential = DeepSeekCredential(
        id: "key-1",
        label: "Production",
        isDefault: true,
        createdAt: Date()
    )
    let event = UsageEvent(
        providerID: "deepseek",
        accountID: credential.id,
        model: "deepseek-chat",
        inputTokens: 100,
        outputTokens: 200,
        totalTokens: 300,
        createdAt: Date(),
        confidence: .observed
    )
    let adapter = DeepSeekProviderAdapter(
        credentialStore: TestDeepSeekCredentialStore(
            storedCredentials: [credential],
            secrets: [credential.id: "sk-test"]
        ),
        usageStore: TestUsageEventStore(events: [event]),
        balanceClient: TestDeepSeekBalanceClient(result: .success(balanceResponse()))
    )

    let snapshot = await adapter.snapshot()

    let account = try #require(snapshot.accounts?.first { $0.id == credential.id })
    #expect(account.name == "Production")
    #expect(account.models.first?.model == "deepseek-chat")
    #expect(account.models.first?.totalTokens == 300)
    #expect(account.models.first?.spendUSD == nil)
    #expect(account.activity?.contains { $0.value == 300 } == true)
}

@Test func deepSeekProviderAdapterFetchesMultipleBalancesConcurrently() async {
    let credentials = [
        DeepSeekCredential(
            id: "key-1",
            label: "One",
            isDefault: true,
            createdAt: Date(timeIntervalSince1970: 0)
        ),
        DeepSeekCredential(
            id: "key-2",
            label: "Two",
            isDefault: false,
            createdAt: Date(timeIntervalSince1970: 1)
        )
    ]
    let gate = DeepSeekBalanceStartGate(targetCount: credentials.count)
    let adapter = DeepSeekProviderAdapter(
        credentialStore: TestDeepSeekCredentialStore(
            storedCredentials: credentials,
            secrets: ["key-1": "sk-one", "key-2": "sk-two"]
        ),
        usageStore: TestUsageEventStore(),
        balanceClient: GatedDeepSeekBalanceClient(gate: gate)
    )

    let snapshot = await adapter.snapshot()

    #expect(snapshot.health == .ready)
    #expect(snapshot.accounts?.filter { $0.health == .ready }.count == 2)
}

@Test func deepSeekProviderAdapterReportsPartialOfficialBalanceSource() async {
    let credentials = [
        DeepSeekCredential(id: "key-1", label: "One", isDefault: true, createdAt: Date()),
        DeepSeekCredential(id: "key-2", label: "Two", isDefault: false, createdAt: Date())
    ]
    let adapter = DeepSeekProviderAdapter(
        credentialStore: TestDeepSeekCredentialStore(
            storedCredentials: credentials,
            secrets: ["key-1": "sk-good", "key-2": "sk-bad"]
        ),
        usageStore: TestUsageEventStore(),
        balanceClient: SelectiveDeepSeekBalanceClient(failingAPIKey: "sk-bad")
    )

    let snapshot = await adapter.snapshot()

    let diagnostic = snapshot.sourceDiagnostics?.first
    #expect(snapshot.health == .ready)
    #expect(diagnostic?.status == .partial)
    #expect(diagnostic?.lastSuccessAt != nil)
    #expect(diagnostic?.lastFailureAt != nil)
}

private struct TestDeepSeekCredentialStore: DeepSeekCredentialStoring {
    let storedCredentials: [DeepSeekCredential]
    var secrets: [String: String] = [:]

    func credentials() throws -> [DeepSeekCredential] { storedCredentials }
    func addCredential(label: String, apiKey: String) throws -> DeepSeekCredential { throw TestProviderError.unsupported }
    func deleteCredential(id: String) throws {}
    func setDefaultCredential(id: String) throws {}
    func readSecret(for id: String) throws -> String? { secrets[id] }
    func resolvedCredentials() throws -> [DeepSeekResolvedCredential] { [] }
    func defaultResolvedCredential() throws -> DeepSeekResolvedCredential? { nil }
    func proxyCredential(for requestAPIKey: String?) throws -> DeepSeekProxyCredential? { nil }
}

private actor TestUsageEventStore: UsageEventStoring {
    private let events: [UsageEvent]

    init(events: [UsageEvent] = []) {
        self.events = events
    }

    func load(providerID: String?) async -> [UsageEvent] {
        guard let providerID else { return events }
        return events.filter { $0.providerID == providerID }
    }
    func append(_ event: UsageEvent) async {}
}

private struct TestDeepSeekBalanceClient: DeepSeekBalanceFetching {
    let result: Result<DeepSeekBalanceResponse, Error>

    func fetchBalance(apiKey: String) async throws -> DeepSeekBalanceResponse {
        try result.get()
    }
}

private struct GatedDeepSeekBalanceClient: DeepSeekBalanceFetching {
    let gate: DeepSeekBalanceStartGate

    func fetchBalance(apiKey: String) async throws -> DeepSeekBalanceResponse {
        await gate.arriveAndWait()
        return balanceResponse()
    }
}

private struct SelectiveDeepSeekBalanceClient: DeepSeekBalanceFetching {
    let failingAPIKey: String

    func fetchBalance(apiKey: String) async throws -> DeepSeekBalanceResponse {
        if apiKey == failingAPIKey {
            throw TestProviderError.failed
        }
        return balanceResponse()
    }
}

private actor DeepSeekBalanceStartGate {
    private let targetCount: Int
    private var startedCount = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []

    init(targetCount: Int) {
        self.targetCount = targetCount
    }

    func arriveAndWait() async {
        startedCount += 1
        if startedCount >= targetCount {
            let waiting = continuations
            continuations.removeAll()
            waiting.forEach { $0.resume() }
            return
        }

        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }
}

private func balanceResponse(total: String = "10.00") -> DeepSeekBalanceResponse {
    DeepSeekBalanceResponse(
        isAvailable: true,
        balanceInfos: [
            DeepSeekBalanceInfo(
                currency: "USD",
                totalBalance: total,
                grantedBalance: "0.00",
                toppedUpBalance: total
            )
        ]
    )
}

private enum TestProviderError: LocalizedError {
    case failed
    case unsupported

    var errorDescription: String? {
        switch self {
        case .failed:
            return "request failed"
        case .unsupported:
            return "unsupported"
        }
    }
}
