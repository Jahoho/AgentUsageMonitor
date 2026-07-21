import AgentUsageCore
import Foundation
import Testing
@testable import AgentUsageMonitor

@Test func quotaProjectionServiceRecordsOnlyEligibleCurrentOfficialCodexBars() async throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let observationStore = CapacityTestObservationStore()
    let service = QuotaProjectionService(
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

    let result = await service.refreshProjections(from: [snapshot], now: now)
    let observations = try await observationStore.load(now: now)

    #expect(result.projections["codex"]?.availabilityReason == .insufficientHistory)
    #expect(result.projections["codex"]?.confidence == .unavailable)
    #expect(result.weeklyReviews["codex"]?.availabilityReason == .insufficientCurrentCycle)
    #expect(observations.map(\.quotaID) == ["codex-session", "codex-weekly"])
    #expect(observations.map(\.remainingFraction) == [0.75, 0.4])
    #expect(observations.allSatisfy { $0.capturedAt == now })
    #expect(observations.allSatisfy { $0.accountScopeID.count == 64 })
    #expect(observations.allSatisfy { $0.accountScopeID.contains("person@example.com") == false })
}

@Test func quotaProjectionRejectsErroredFallbackStaleUnscopedAndUnsupportedSnapshots() async throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let observationStore = CapacityTestObservationStore()
    let service = QuotaProjectionService(
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
            updatedAt: now.addingTimeInterval(-QuotaProjectionService.maximumSnapshotAge - 1),
            bars: validBars
        ),
        capacitySnapshot(updatedAt: now, accountValue: nil, bars: validBars),
        capacitySnapshot(updatedAt: now, providerID: "openrouter", bars: validBars),
        capacitySnapshot(updatedAt: now, sourceStatus: .failure, bars: validBars)
    ]

    for rejectedSnapshot in rejectedSnapshots {
        _ = await service.refreshProjections(from: [rejectedSnapshot], now: now)
    }

    #expect(try await observationStore.load(now: now).isEmpty)
}

@Test func quotaProjectionFailsClosedWithoutLoadingHistoryWhenCurrentQuotaFails() async throws {
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
    let service = QuotaProjectionService(
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

    let result = await service.refreshProjections(from: [failedSnapshot], now: now)

    #expect(result.projections["codex"]?.confidence == .unavailable)
    #expect(result.projections["codex"]?.availabilityReason == .currentQuotaUnavailable)
    #expect(result.weeklyReviews["codex"]?.availabilityReason == .currentQuotaUnavailable)
    #expect(await observationStore.loadCallCount() == 0)
}

@Test func quotaProjectionExplainsMissingResetAndHistoryFailures() async {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let missingResetService = QuotaProjectionService(
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

    let missingResetResult = await missingResetService.refreshProjections(
        from: [missingReset],
        now: now
    )

    #expect(missingResetResult.projections["codex"]?.confidence == .unavailable)
    #expect(missingResetResult.projections["codex"]?.availabilityReason == .resetUnavailable)

    let failingHistoryService = QuotaProjectionService(
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

    let failingHistoryResult = await failingHistoryService.refreshProjections(
        from: [currentSnapshot],
        now: now
    )

    #expect(failingHistoryResult.projections["codex"]?.confidence == .unavailable)
    #expect(failingHistoryResult.projections["codex"]?.availabilityReason == .historyUnavailable)
    #expect(failingHistoryResult.weeklyReviews["codex"]?.availabilityReason == .historyUnavailable)
}

@Test func quotaProjectionScopeIsStablePerInstallationAndSeparatesAccounts() async throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let secretStore = CapacityTestSecretStore()
    let firstStore = CapacityTestObservationStore()
    let secondStore = CapacityTestObservationStore()
    let firstService = QuotaProjectionService(
        observationStore: firstStore,
        secretStore: secretStore
    )
    let secondService = QuotaProjectionService(
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

    _ = await firstService.refreshProjections(
        from: [capacitySnapshot(updatedAt: now, accountValue: "person@example.com", bars: bars)],
        now: now
    )
    _ = await secondService.refreshProjections(
        from: [capacitySnapshot(updatedAt: now, accountValue: "PERSON@example.com", bars: bars)],
        now: now
    )
    _ = await secondService.refreshProjections(
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

@Test func quotaProjectionServiceBuildsWeeklyReviewFromRecordedOfficialSamples() async throws {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let resetAt = start.addingTimeInterval(7 * 24 * 60 * 60)
    let observationStore = CapacityTestObservationStore()
    let service = QuotaProjectionService(
        observationStore: observationStore,
        secretStore: CapacityTestSecretStore()
    )

    _ = await service.refreshProjections(
        from: [
            capacitySnapshot(
                updatedAt: start,
                bars: [capacityBar(id: "codex-weekly", remainingFraction: 1, resetAt: resetAt)]
            )
        ],
        now: start
    )
    let later = start.addingTimeInterval(60 * 60)
    let result = await service.refreshProjections(
        from: [
            capacitySnapshot(
                updatedAt: later,
                bars: [capacityBar(id: "codex-weekly", remainingFraction: 0.9, resetAt: resetAt)]
            )
        ],
        now: later
    )

    let review = try #require(result.weeklyReviews["codex"])
    let cycle = try #require(review.currentCycle)
    #expect(review.confidence == .observed)
    #expect(cycle.usageScope == .cycleToDate)
    #expect(abs(cycle.observedUsedFraction - 0.1) < 0.000_001)
}

@Test func quotaProjectionServiceKeepsLegacyLongPrimaryHistoryAfterWeeklyIDCorrection() async throws {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let resetAt = start.addingTimeInterval(7 * 24 * 60 * 60)
    let service = QuotaProjectionService(
        observationStore: CapacityTestObservationStore(),
        secretStore: CapacityTestSecretStore()
    )

    for sample in 0...12 {
        let capturedAt = start.addingTimeInterval(TimeInterval(sample) * 30 * 60)
        _ = await service.refreshProjections(
            from: [
                capacitySnapshot(
                    updatedAt: capturedAt,
                    bars: [
                        capacityBar(
                            id: "codex-session",
                            remainingFraction: 1 - (Double(sample) * 0.01),
                            resetAt: resetAt
                        )
                    ]
                )
            ],
            now: capturedAt
        )
    }

    let currentAt = start.addingTimeInterval(6.5 * 60 * 60)
    let result = await service.refreshProjections(
        from: [
            capacitySnapshot(
                updatedAt: currentAt,
                bars: [
                    capacityBar(
                        id: "codex-weekly",
                        remainingFraction: 0.87,
                        resetAt: resetAt
                    )
                ]
            )
        ],
        now: currentAt
    )

    let projection = try #require(result.projections["codex"])
    #expect(projection.confidence == .estimated)
    #expect(projection.constrainingQuotaID == "codex-weekly")
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
