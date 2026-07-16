import AgentUsageCore
import Foundation
import Testing
@testable import AgentUsageMonitor

@Test func providerMonitorServiceReturnsTimeoutSnapshotForSlowAdapter() async {
    let adapter = TestProviderAdapter(
        providerID: "slow",
        providerName: "Slow",
        providerKind: .subscription,
        snapshot: testSnapshot(id: "slow", name: "Slow"),
        delayMilliseconds: 500
    )
    let service = ProviderMonitorService(adapters: [adapter], providerTimeoutSeconds: 0.01)

    let snapshots = await service.loadProviderSnapshots()

    #expect(snapshots.count == 1)
    #expect(snapshots[0].id == "slow")
    #expect(snapshots[0].health == .error)
    #expect(snapshots[0].metrics.first { $0.id == "refresh-timeout" } != nil)
    let diagnostic = snapshots[0].sourceDiagnostics?.first
    #expect(diagnostic?.status == .failure)
    #expect(diagnostic?.attemptedAt == diagnostic?.lastFailureAt)
}

@Test func providerMonitorServiceTimesOutBlockingAdapterWithoutWaitingForIt() async {
    let adapter = BlockingProviderAdapter(
        providerID: "blocked",
        providerName: "Blocked",
        providerKind: .subscription,
        blockSeconds: 1
    )
    let service = ProviderMonitorService(adapters: [adapter], providerTimeoutSeconds: 0.05)
    let startedAt = Date()

    let snapshots = await service.loadProviderSnapshots()

    #expect(Date().timeIntervalSince(startedAt) < 0.5)
    #expect(snapshots.count == 1)
    #expect(snapshots[0].id == "blocked")
    #expect(snapshots[0].health == .error)
    #expect(snapshots[0].metrics.first { $0.id == "refresh-timeout" } != nil)
}

@Test func providerMonitorServiceReturnsFastAdapterSnapshot() async {
    let adapter = TestProviderAdapter(
        providerID: "codex",
        providerName: "Codex",
        providerKind: .subscription,
        snapshot: testSnapshot(id: "codex", name: "Codex")
    )
    let service = ProviderMonitorService(adapters: [adapter], providerTimeoutSeconds: 1)

    let snapshots = await service.loadProviderSnapshots()

    #expect(snapshots.map(\.id) == ["codex"])
    #expect(snapshots[0].health == .ready)
}

@Test func providerMonitorServiceStartsAdaptersConcurrently() async {
    let gate = ConcurrentStartGate(targetCount: 2)
    let service = ProviderMonitorService(
        adapters: [
            GatedProviderAdapter(providerID: "codex", providerName: "Codex", gate: gate),
            GatedProviderAdapter(providerID: "deepseek", providerName: "DeepSeek", gate: gate)
        ],
        providerTimeoutSeconds: 0.2
    )

    let snapshots = await service.loadProviderSnapshots()

    #expect(snapshots.map(\.id) == ["codex", "deepseek"])
    #expect(snapshots.allSatisfy { $0.health == .ready })
}

@MainActor
@Test func dashboardRefreshUsesInjectedProviderService() async {
    let codex = testSnapshot(id: "codex", name: "Codex", remainingFraction: 0.72)
    let adapter = TestProviderAdapter(
        providerID: "codex",
        providerName: "Codex",
        providerKind: .subscription,
        snapshot: codex
    )
    let viewModel = DashboardViewModel(
        providerMonitorService: ProviderMonitorService(adapters: [adapter], providerTimeoutSeconds: 1),
        deepSeekCredentialStore: EmptyDeepSeekCredentialStore(),
        openRouterCredentialStore: EmptyOpenRouterCredentialStore(),
        usageStore: InMemoryUsageEventStore()
    )

    await viewModel.refresh()

    #expect(viewModel.snapshots.map(\.id) == ["overview", "codex"])
    #expect(viewModel.menuBarStatus.providerID == "codex")
    #expect(viewModel.menuBarStatus.remainingFraction == 0.72)
}

@MainActor
@Test func dashboardRefreshDoesNotReloadCredentialsOrReconfigureLocalServices() async {
    let credentialStore = CountingDeepSeekCredentialStore()
    let adapter = TestProviderAdapter(
        providerID: "codex",
        providerName: "Codex",
        providerKind: .subscription,
        snapshot: testSnapshot(id: "codex", name: "Codex")
    )
    let viewModel = DashboardViewModel(
        providerMonitorService: ProviderMonitorService(adapters: [adapter], providerTimeoutSeconds: 1),
        deepSeekCredentialStore: credentialStore,
        openRouterCredentialStore: EmptyOpenRouterCredentialStore(),
        usageStore: InMemoryUsageEventStore()
    )

    await viewModel.refresh()
    await viewModel.refresh()

    #expect(credentialStore.credentialsCallCount == 1)
    #expect(credentialStore.proxyCredentialCallCount == 0)
}

@MainActor
@Test func dashboardRefreshKeepsPreviousSnapshotWhenProviderRefreshTimesOut() async throws {
    let previousSuccessAt = Date(timeIntervalSince1970: 1_700_000_000)
    let latestFailureAt = Date(timeIntervalSince1970: 1_700_000_100)
    let adapter = SequencedProviderAdapter(
        providerID: "deepseek",
        providerName: "DeepSeek",
        providerKind: .api,
        snapshots: [
            testSnapshot(
                id: "deepseek",
                name: "DeepSeek",
                kind: .api,
                remainingFraction: 0.72,
                sourceDiagnostics: [
                    ProviderSourceDiagnostic(
                        id: "deepseek-balance-api",
                        name: "Official balance API",
                        confidence: .official,
                        status: .success,
                        attemptedAt: previousSuccessAt,
                        lastSuccessAt: previousSuccessAt
                    )
                ]
            ),
            ProviderSnapshot(
                id: "deepseek",
                name: "DeepSeek",
                kind: .api,
                health: .error,
                headline: "DeepSeek refresh timed out",
                metrics: [],
                bars: [],
                sourceDiagnostics: [
                    ProviderSourceDiagnostic(
                        id: "deepseek-balance-api",
                        name: "Official balance API",
                        confidence: .official,
                        status: .failure,
                        attemptedAt: latestFailureAt,
                        lastFailureAt: latestFailureAt
                    )
                ],
                notes: [],
                actions: []
            )
        ]
    )
    let viewModel = DashboardViewModel(
        providerMonitorService: ProviderMonitorService(adapters: [adapter], providerTimeoutSeconds: 1),
        deepSeekCredentialStore: EmptyDeepSeekCredentialStore(),
        openRouterCredentialStore: EmptyOpenRouterCredentialStore(),
        usageStore: InMemoryUsageEventStore()
    )

    await viewModel.refresh()
    await viewModel.refresh()

    let deepseek = try #require(viewModel.snapshots.first { $0.id == "deepseek" })
    #expect(deepseek.health == .ready)
    #expect(deepseek.bars.first?.remainingFraction == 0.72)
    #expect(deepseek.notes.contains { $0.contains("Latest refresh failed") })
    let diagnostic = try #require(deepseek.sourceDiagnostics?.first)
    #expect(diagnostic.isFallback)
    #expect(diagnostic.lastSuccessAt == previousSuccessAt)
    #expect(diagnostic.lastFailureAt == latestFailureAt)
}

@MainActor
@Test func dashboardRefreshDoesNotPreservePreviousCodexSnapshotWhenOfficialRefreshFails() async throws {
    let previousSuccessAt = Date(timeIntervalSince1970: 1_700_000_000)
    let latestFailureAt = Date(timeIntervalSince1970: 1_700_000_100)
    let adapter = SequencedProviderAdapter(
        providerID: "codex",
        providerName: "Codex",
        providerKind: .subscription,
        snapshots: [
            testSnapshot(
                id: "codex",
                name: "Codex",
                remainingFraction: 0.72,
                sourceDiagnostics: [
                    ProviderSourceDiagnostic(
                        id: "codex-oauth-api",
                        name: "OAuth API",
                        confidence: .official,
                        status: .success,
                        attemptedAt: previousSuccessAt,
                        lastSuccessAt: previousSuccessAt
                    )
                ]
            ),
            ProviderSnapshot(
                id: "codex",
                name: "Codex",
                kind: .subscription,
                health: .error,
                headline: "Official Codex usage unavailable",
                metrics: [],
                bars: [],
                sourceDiagnostics: [
                    ProviderSourceDiagnostic(
                        id: "codex-oauth-api",
                        name: "OAuth API",
                        confidence: .official,
                        status: .failure,
                        attemptedAt: latestFailureAt,
                        lastFailureAt: latestFailureAt
                    )
                ],
                notes: ["Official Codex usage is unavailable."],
                actions: []
            )
        ],
        freshnessPolicy: .requireCurrent
    )
    let viewModel = DashboardViewModel(
        providerMonitorService: ProviderMonitorService(adapters: [adapter], providerTimeoutSeconds: 1),
        deepSeekCredentialStore: EmptyDeepSeekCredentialStore(),
        openRouterCredentialStore: EmptyOpenRouterCredentialStore(),
        usageStore: InMemoryUsageEventStore()
    )

    await viewModel.refresh()
    await viewModel.refresh()

    let codex = try #require(viewModel.snapshots.first { $0.id == "codex" })
    #expect(codex.health == .error)
    #expect(codex.bars.isEmpty)
    #expect(codex.notes.contains("Official Codex usage is unavailable."))
    let diagnostic = try #require(codex.sourceDiagnostics?.first)
    #expect(diagnostic.isFallback == false)
    #expect(diagnostic.lastSuccessAt == previousSuccessAt)
    #expect(diagnostic.lastFailureAt == latestFailureAt)
}

@MainActor
@Test func dashboardProviderTimeoutPreservesOnlyCodexObservedActivityAndSourceHistory() async throws {
    let previousSuccessAt = Date(timeIntervalSince1970: 1_700_000_000)
    let timeoutAt = Date(timeIntervalSince1970: 1_700_000_100)
    let previous = ProviderSnapshot(
        id: "codex",
        name: "Codex",
        kind: .subscription,
        health: .ready,
        headline: "Synced from OAuth API",
        metrics: [
            UsageMetric(
                id: "today-tokens",
                label: "Today local tokens",
                value: "4.0K",
                confidence: .observed
            )
        ],
        bars: [
            UsageBar(
                id: "codex-session",
                label: "Session",
                remainingFraction: 0.72,
                usedText: "72% left",
                resetText: "Reset unknown",
                confidence: .official
            )
        ],
        activity: [
            UsageActivityBucket(
                id: "hour-10",
                label: "10:00",
                value: 4_000,
                valueText: "4.0K",
                confidence: .observed
            )
        ],
        sourceDiagnostics: [
            ProviderSourceDiagnostic(
                id: "codex-oauth-api",
                name: "OAuth API",
                confidence: .official,
                status: .success,
                attemptedAt: previousSuccessAt,
                lastSuccessAt: previousSuccessAt
            )
        ],
        notes: [],
        actions: []
    )
    let timedOut = ProviderSnapshot(
        id: "codex",
        name: "Codex",
        kind: .subscription,
        health: .error,
        headline: "Codex refresh timed out",
        metrics: [
            UsageMetric(
                id: "refresh-timeout",
                label: "Refresh",
                value: "Timed out",
                confidence: .unavailable
            )
        ],
        bars: [],
        sourceDiagnostics: [
            ProviderSourceDiagnostic(
                id: "provider-refresh",
                name: "Provider refresh",
                confidence: .unavailable,
                status: .failure,
                attemptedAt: timeoutAt,
                lastFailureAt: timeoutAt
            )
        ],
        notes: [],
        actions: []
    )
    let adapter = SequencedProviderAdapter(
        providerID: "codex",
        providerName: "Codex",
        providerKind: .subscription,
        snapshots: [previous, timedOut],
        freshnessPolicy: .requireCurrent
    )
    let viewModel = DashboardViewModel(
        providerMonitorService: ProviderMonitorService(adapters: [adapter], providerTimeoutSeconds: 1),
        deepSeekCredentialStore: EmptyDeepSeekCredentialStore(),
        openRouterCredentialStore: EmptyOpenRouterCredentialStore(),
        usageStore: InMemoryUsageEventStore()
    )

    await viewModel.refresh()
    await viewModel.refresh()

    let codex = try #require(viewModel.snapshots.first { $0.id == "codex" })
    #expect(codex.health == .error)
    #expect(codex.bars.isEmpty)
    #expect(codex.quotaCreditBank == nil)
    #expect(codex.metrics.first { $0.id == "today-tokens" }?.confidence == .observed)
    #expect(codex.activity?.first?.value == 4_000)
    #expect(codex.notes.contains { $0.contains("no Codex quota was preserved") })

    let oauth = try #require(codex.sourceDiagnostics?.first { $0.id == "codex-oauth-api" })
    #expect(oauth.status == .failure)
    #expect(oauth.lastSuccessAt == previousSuccessAt)
    #expect(oauth.lastFailureAt == timeoutAt)
    #expect(oauth.isFallback == false)
}

@MainActor
@Test func dashboardRefreshDoesNotPreservePreviousOpenRouterSnapshotWhenOfficialRefreshFails() async throws {
    let previousSuccessAt = Date(timeIntervalSince1970: 1_700_000_000)
    let latestFailureAt = Date(timeIntervalSince1970: 1_700_000_100)
    let adapter = SequencedProviderAdapter(
        providerID: "openrouter",
        providerName: "OpenRouter",
        providerKind: .api,
        snapshots: [
            testSnapshot(
                id: "openrouter",
                name: "OpenRouter",
                kind: .api,
                remainingFraction: 0.72,
                sourceDiagnostics: [
                    ProviderSourceDiagnostic(
                        id: "openrouter-current-key-api",
                        name: "Official current-key API",
                        confidence: .official,
                        status: .success,
                        attemptedAt: previousSuccessAt,
                        lastSuccessAt: previousSuccessAt
                    )
                ]
            ),
            ProviderSnapshot(
                id: "openrouter",
                name: "OpenRouter",
                kind: .api,
                health: .error,
                headline: "OpenRouter official usage sync failed",
                metrics: [],
                bars: [],
                sourceDiagnostics: [
                    ProviderSourceDiagnostic(
                        id: "openrouter-current-key-api",
                        name: "Official current-key API",
                        confidence: .official,
                        status: .failure,
                        attemptedAt: latestFailureAt,
                        lastFailureAt: latestFailureAt
                    )
                ],
                notes: ["Current official usage is unavailable."],
                actions: []
            )
        ],
        freshnessPolicy: .requireCurrent
    )
    let viewModel = DashboardViewModel(
        providerMonitorService: ProviderMonitorService(adapters: [adapter], providerTimeoutSeconds: 1),
        deepSeekCredentialStore: EmptyDeepSeekCredentialStore(),
        openRouterCredentialStore: EmptyOpenRouterCredentialStore(),
        usageStore: InMemoryUsageEventStore()
    )

    await viewModel.refresh()
    await viewModel.refresh()

    let openRouter = try #require(viewModel.snapshots.first { $0.id == "openrouter" })
    #expect(openRouter.health == .error)
    #expect(openRouter.bars.isEmpty)
    #expect(openRouter.notes == ["Current official usage is unavailable."])
    let diagnostic = try #require(openRouter.sourceDiagnostics?.first)
    #expect(diagnostic.isFallback == false)
    #expect(diagnostic.lastSuccessAt == previousSuccessAt)
    #expect(diagnostic.lastFailureAt == latestFailureAt)
}

@Test func localCommandReaderTimesOutHungCommands() {
    let reader = LocalCommandReader(timeoutSeconds: 0.05)
    let startedAt = Date()

    let output = reader.firstSuccessfulOutput(commands: [["sleep", "1"]])

    #expect(output == nil)
    #expect(Date().timeIntervalSince(startedAt) < 0.5)
}

private struct TestProviderAdapter: ProviderSnapshotAdapter {
    let registration: ProviderRegistration
    let snapshot: ProviderSnapshot
    var delayMilliseconds = 0

    init(
        providerID: String,
        providerName: String,
        providerKind: ProviderKind,
        snapshot: ProviderSnapshot,
        delayMilliseconds: Int = 0,
        freshnessPolicy: ProviderSnapshotFreshnessPolicy = .preserveLastKnown
    ) {
        self.registration = testRegistration(
            id: providerID,
            name: providerName,
            kind: providerKind,
            freshnessPolicy: freshnessPolicy
        )
        self.snapshot = snapshot
        self.delayMilliseconds = delayMilliseconds
    }

    func snapshot() async -> ProviderSnapshot {
        if delayMilliseconds > 0 {
            try? await Task.sleep(for: .milliseconds(delayMilliseconds))
        }
        return snapshot
    }
}

private struct BlockingProviderAdapter: ProviderSnapshotAdapter {
    let registration: ProviderRegistration
    let blockSeconds: TimeInterval

    init(
        providerID: String,
        providerName: String,
        providerKind: ProviderKind,
        blockSeconds: TimeInterval
    ) {
        self.registration = testRegistration(id: providerID, name: providerName, kind: providerKind)
        self.blockSeconds = blockSeconds
    }

    func snapshot() async -> ProviderSnapshot {
        let deadline = Date().addingTimeInterval(blockSeconds)
        while Date() < deadline {}
        return testSnapshot(id: providerID, name: providerName)
    }
}

private struct GatedProviderAdapter: ProviderSnapshotAdapter {
    let registration: ProviderRegistration
    let gate: ConcurrentStartGate

    init(providerID: String, providerName: String, gate: ConcurrentStartGate) {
        self.registration = testRegistration(id: providerID, name: providerName, kind: .subscription)
        self.gate = gate
    }

    func snapshot() async -> ProviderSnapshot {
        await gate.arriveAndWait()
        return testSnapshot(id: providerID, name: providerName)
    }
}

private actor ConcurrentStartGate {
    private let targetCount: Int
    private var startedCount = 0
    private var continuations: [CheckedContinuation<Void, Never>] = []

    init(targetCount: Int) {
        self.targetCount = targetCount
    }

    func arriveAndWait() async {
        startedCount += 1

        if startedCount >= targetCount {
            let continuationsToResume = continuations
            continuations.removeAll()
            continuationsToResume.forEach { $0.resume() }
            return
        }

        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }
}

private actor SequencedProviderAdapter: ProviderSnapshotAdapter {
    nonisolated let registration: ProviderRegistration

    private var snapshots: [ProviderSnapshot]

    init(
        providerID: String,
        providerName: String,
        providerKind: ProviderKind,
        snapshots: [ProviderSnapshot],
        freshnessPolicy: ProviderSnapshotFreshnessPolicy = .preserveLastKnown
    ) {
        self.registration = testRegistration(
            id: providerID,
            name: providerName,
            kind: providerKind,
            freshnessPolicy: freshnessPolicy
        )
        self.snapshots = snapshots
    }

    func snapshot() async -> ProviderSnapshot {
        if snapshots.count > 1 {
            return snapshots.removeFirst()
        }

        return snapshots[0]
    }
}

private func testRegistration(
    id: String,
    name: String,
    kind: ProviderKind,
    freshnessPolicy: ProviderSnapshotFreshnessPolicy = .preserveLastKnown
) -> ProviderRegistration {
    ProviderRegistration(
        id: id,
        displayName: name,
        kind: kind,
        navigation: ProviderNavigationMetadata(
            title: name,
            icon: .brand(resourceName: id)
        ),
        freshnessPolicy: freshnessPolicy
    )
}

private struct EmptyDeepSeekCredentialStore: DeepSeekCredentialStoring {
    func credentials() throws -> [DeepSeekCredential] { [] }
    func addCredential(label: String, apiKey: String) throws -> DeepSeekCredential { throw TestError.unsupported }
    func deleteCredential(id: String) throws {}
    func setDefaultCredential(id: String) throws {}
    func readSecret(for id: String) throws -> String? { nil }
    func resolvedCredentials() throws -> [DeepSeekResolvedCredential] { [] }
    func defaultResolvedCredential() throws -> DeepSeekResolvedCredential? { nil }
    func proxyCredential(for requestAPIKey: String?) throws -> DeepSeekProxyCredential? { nil }
}

private struct EmptyOpenRouterCredentialStore: OpenRouterCredentialStoring {
    func credentials() throws -> [OpenRouterCredential] { [] }
    func addCredential(label: String, apiKey: String) throws -> OpenRouterCredential { throw TestError.unsupported }
    func deleteCredential(id: String) throws {}
    func setDefaultCredential(id: String) throws {}
    func readSecret(for id: String) throws -> String? { nil }
    func resolvedCredentials() throws -> [OpenRouterResolvedCredential] { [] }
    func defaultResolvedCredential() throws -> OpenRouterResolvedCredential? { nil }
}

private final class CountingDeepSeekCredentialStore: DeepSeekCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var storedCredentialsCallCount = 0
    private var storedProxyCredentialCallCount = 0

    var credentialsCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedCredentialsCallCount
    }

    var proxyCredentialCallCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedProxyCredentialCallCount
    }

    func credentials() throws -> [DeepSeekCredential] {
        lock.lock()
        storedCredentialsCallCount += 1
        lock.unlock()
        return []
    }

    func addCredential(label: String, apiKey: String) throws -> DeepSeekCredential {
        throw TestError.unsupported
    }

    func deleteCredential(id: String) throws {}
    func setDefaultCredential(id: String) throws {}
    func readSecret(for id: String) throws -> String? { nil }
    func resolvedCredentials() throws -> [DeepSeekResolvedCredential] { [] }
    func defaultResolvedCredential() throws -> DeepSeekResolvedCredential? { nil }

    func proxyCredential(for requestAPIKey: String?) throws -> DeepSeekProxyCredential? {
        lock.lock()
        storedProxyCredentialCallCount += 1
        lock.unlock()
        return nil
    }
}

private actor InMemoryUsageEventStore: UsageEventStoring {
    private var events: [UsageEvent]

    init(events: [UsageEvent] = []) {
        self.events = events
    }

    func load(providerID: String?) async -> [UsageEvent] {
        guard let providerID else {
            return events
        }
        return events.filter { $0.providerID == providerID }
    }

    func append(_ event: UsageEvent) async {
        events.append(event)
    }
}

private func testSnapshot(
    id: String,
    name: String,
    kind: ProviderKind = .subscription,
    remainingFraction: Double? = nil,
    sourceDiagnostics: [ProviderSourceDiagnostic]? = nil
) -> ProviderSnapshot {
    ProviderSnapshot(
        id: id,
        name: name,
        kind: kind,
        health: .ready,
        headline: "Ready",
        metrics: [],
        bars: [
            UsageBar(
                id: "\(id)-quota",
                label: "Quota",
                remainingFraction: remainingFraction,
                usedText: remainingFraction.map { "\(Int(($0 * 100).rounded()))% left" } ?? "Unavailable",
                resetText: "Unknown",
                confidence: remainingFraction == nil ? .unavailable : .official
            )
        ],
        sourceDiagnostics: sourceDiagnostics,
        notes: [],
        actions: []
    )
}

private enum TestError: Error {
    case unsupported
}
