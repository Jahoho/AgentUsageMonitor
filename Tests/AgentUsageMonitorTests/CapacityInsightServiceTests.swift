import AgentUsageCore
import Foundation
import Testing
@testable import AgentUsageMonitor

@Test func capacityInsightRecordsOnlyEligibleCurrentOfficialCodexBars() async throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let observationStore = CapacityTestObservationStore()
    let service = CapacityInsightService(
        observationStore: observationStore,
        secretStore: CapacityTestSecretStore()
    )
    let snapshot = capacitySnapshot(
        updatedAt: now,
        bars: [
            capacityBar(
                id: "codex-session",
                remainingFraction: 0.75,
                resetAt: now.addingTimeInterval(3_600)
            ),
            capacityBar(
                id: "codex-weekly",
                remainingFraction: 0.4,
                resetAt: now.addingTimeInterval(604_800)
            ),
            capacityBar(
                id: "observed-window",
                remainingFraction: 0.3,
                resetAt: now.addingTimeInterval(3_600),
                confidence: .observed
            ),
            capacityBar(
                id: "missing-reset",
                remainingFraction: 0.2,
                resetAt: nil
            )
        ]
    )

    let insights = await service.refreshInsights(from: [snapshot], now: now)
    let observations = try await observationStore.load(now: now)

    #expect(insights["codex"]?.weather == .learning)
    #expect(insights["codex"]?.confidence == .unavailable)
    #expect(observations.map(\.quotaID) == ["codex-session", "codex-weekly"])
    #expect(observations.map(\.remainingFraction) == [0.75, 0.4])
    #expect(observations.allSatisfy { $0.capturedAt == now })
    #expect(observations.allSatisfy { $0.accountScopeID.count == 64 })
    #expect(observations.allSatisfy { $0.accountScopeID.contains("person@example.com") == false })
}

@Test func capacityInsightRejectsErroredFallbackStaleUnscopedAndUnsupportedSnapshots() async throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let observationStore = CapacityTestObservationStore()
    let service = CapacityInsightService(
        observationStore: observationStore,
        secretStore: CapacityTestSecretStore()
    )
    let validBars = [
        capacityBar(
            id: "codex-session",
            remainingFraction: 0.5,
            resetAt: now.addingTimeInterval(3_600)
        )
    ]
    let rejectedSnapshots = [
        capacitySnapshot(updatedAt: now, health: .error, bars: validBars),
        capacitySnapshot(updatedAt: now, isFallback: true, bars: validBars),
        capacitySnapshot(
            updatedAt: now.addingTimeInterval(-CapacityInsightService.maximumSnapshotAge - 1),
            bars: validBars
        ),
        capacitySnapshot(updatedAt: now, accountValue: nil, bars: validBars),
        capacitySnapshot(updatedAt: now, providerID: "openrouter", bars: validBars),
        capacitySnapshot(updatedAt: now, sourceStatus: .failure, bars: validBars)
    ]

    for rejectedSnapshot in rejectedSnapshots {
        _ = await service.refreshInsights(from: [rejectedSnapshot], now: now)
    }

    #expect(try await observationStore.load(now: now).isEmpty)
}

@Test func capacityInsightFailsClosedWithoutLoadingHistoryWhenCurrentQuotaFails() async throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let historicalObservation = QuotaObservation(
        providerID: "codex",
        accountScopeID: "historical-scope",
        quotaID: "codex-session",
        remainingFraction: 0.8,
        capturedAt: now.addingTimeInterval(-1_800),
        resetAt: now.addingTimeInterval(3_600)
    )
    let observationStore = CapacityTestObservationStore(observations: [historicalObservation])
    let service = CapacityInsightService(
        observationStore: observationStore,
        secretStore: CapacityTestSecretStore()
    )
    let failedSnapshot = capacitySnapshot(
        updatedAt: now,
        health: .error,
        bars: [
            capacityBar(
                id: "codex-session",
                remainingFraction: 0.7,
                resetAt: now.addingTimeInterval(3_600)
            )
        ]
    )

    let insights = await service.refreshInsights(from: [failedSnapshot], now: now)

    #expect(insights["codex"]?.weather == .fog)
    #expect(insights["codex"]?.availabilityReason == .currentQuotaUnavailable)
    #expect(await observationStore.loadCallCount() == 0)
}

@Test func capacityInsightExplainsMissingResetAndHistoryFailures() async {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let missingResetService = CapacityInsightService(
        observationStore: CapacityTestObservationStore(),
        secretStore: CapacityTestSecretStore()
    )
    let missingReset = capacitySnapshot(
        updatedAt: now,
        bars: [
            capacityBar(
                id: "codex-session",
                remainingFraction: 0.7,
                resetAt: nil
            )
        ]
    )

    let missingResetInsights = await missingResetService.refreshInsights(
        from: [missingReset],
        now: now
    )

    #expect(missingResetInsights["codex"]?.weather == .fog)
    #expect(missingResetInsights["codex"]?.availabilityReason == .resetUnavailable)

    let failingHistoryService = CapacityInsightService(
        observationStore: CapacityTestObservationStore(shouldFailLoading: true),
        secretStore: CapacityTestSecretStore()
    )
    let currentSnapshot = capacitySnapshot(
        updatedAt: now,
        bars: [
            capacityBar(
                id: "codex-session",
                remainingFraction: 0.7,
                resetAt: now.addingTimeInterval(3_600)
            )
        ]
    )

    let failingHistoryInsights = await failingHistoryService.refreshInsights(
        from: [currentSnapshot],
        now: now
    )

    #expect(failingHistoryInsights["codex"]?.weather == .fog)
    #expect(failingHistoryInsights["codex"]?.availabilityReason == .historyUnavailable)
}

@Test func capacityInsightScopeIsStablePerInstallationAndSeparatesAccounts() async throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let secretStore = CapacityTestSecretStore()
    let firstStore = CapacityTestObservationStore()
    let secondStore = CapacityTestObservationStore()
    let firstService = CapacityInsightService(
        observationStore: firstStore,
        secretStore: secretStore
    )
    let secondService = CapacityInsightService(
        observationStore: secondStore,
        secretStore: secretStore
    )
    let bars = [
        capacityBar(
            id: "codex-weekly",
            remainingFraction: 0.6,
            resetAt: now.addingTimeInterval(604_800)
        )
    ]

    _ = await firstService.refreshInsights(
        from: [capacitySnapshot(updatedAt: now, accountValue: "person@example.com", bars: bars)],
        now: now
    )
    _ = await secondService.refreshInsights(
        from: [capacitySnapshot(updatedAt: now, accountValue: "PERSON@example.com", bars: bars)],
        now: now
    )
    _ = await secondService.refreshInsights(
        from: [capacitySnapshot(updatedAt: now, accountValue: "other@example.com", bars: bars)],
        now: now
    )

    let firstObservations = try await firstStore.load(now: now)
    let firstScope = try #require(firstObservations.first?.accountScopeID)
    let secondObservations = try await secondStore.load(now: now)
    let storedScopeKey = try secretStore.read(account: KeychainAccount.quotaHistoryScopeKey)
    let scopeKey = try #require(storedScopeKey)

    #expect(secondObservations.count == 2)
    #expect(secondObservations[0].accountScopeID == firstScope)
    #expect(secondObservations[1].accountScopeID != firstScope)
    #expect(scopeKey.contains("person@example.com") == false)
}

private actor CapacityTestObservationStore: QuotaObservationStoring {
    private var observations: [QuotaObservation]
    private let shouldFailLoading: Bool
    private var loadCalls = 0

    init(
        observations: [QuotaObservation] = [],
        shouldFailLoading: Bool = false
    ) {
        self.observations = observations
        self.shouldFailLoading = shouldFailLoading
    }

    func record(_ candidates: [QuotaObservation], now: Date) async throws {
        observations.append(contentsOf: candidates)
    }

    func load(now: Date) async throws -> [QuotaObservation] {
        loadCalls += 1
        if shouldFailLoading {
            throw CapacityTestObservationStoreError.loadFailed
        }
        return observations
    }

    func loadCallCount() -> Int {
        loadCalls
    }
}

private enum CapacityTestObservationStoreError: Error {
    case loadFailed
}

private final class CapacityTestSecretStore: SecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func save(_ value: String, account: String) throws {
        lock.lock()
        values[account] = value
        lock.unlock()
    }

    func read(account: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[account]
    }

    func delete(account: String) throws {
        lock.lock()
        values.removeValue(forKey: account)
        lock.unlock()
    }
}

private func capacitySnapshot(
    updatedAt: Date,
    providerID: String = "codex",
    health: ProviderHealth = .ready,
    accountValue: String? = "person@example.com",
    isFallback: Bool = false,
    sourceStatus: ProviderSourceStatus = .success,
    bars: [UsageBar]
) -> ProviderSnapshot {
    ProviderSnapshot(
        id: providerID,
        name: providerID.capitalized,
        kind: .subscription,
        updatedAt: updatedAt,
        health: health,
        headline: "Current official quota",
        metrics: accountValue.map { value in
            [
                UsageMetric(
                    id: "account",
                    label: "Account",
                    value: value,
                    confidence: .official
                )
            ]
        } ?? [],
        bars: bars,
        sourceDiagnostics: [
            ProviderSourceDiagnostic(
                id: "official-source",
                name: "Official source",
                confidence: .official,
                status: sourceStatus,
                attemptedAt: updatedAt,
                lastSuccessAt: sourceStatus == .success ? updatedAt : nil,
                lastFailureAt: sourceStatus == .failure ? updatedAt : nil,
                isFallback: isFallback
            )
        ],
        notes: [],
        actions: []
    )
}

private func capacityBar(
    id: String,
    remainingFraction: Double?,
    resetAt: Date?,
    confidence: UsageConfidence = .official
) -> UsageBar {
    UsageBar(
        id: id,
        label: id,
        remainingFraction: remainingFraction,
        usedText: "Current",
        resetText: "Current",
        resetAt: resetAt,
        confidence: confidence
    )
}
