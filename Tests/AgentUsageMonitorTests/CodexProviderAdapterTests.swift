import AgentUsageCore
import Foundation
import Testing
@testable import AgentUsageMonitor

@Test func codexProviderAdapterReturnsErrorWhenOfficialSourcesTimeout() async {
    let adapter = CodexProviderAdapter(
        commandReader: TestLocalCommandReader(output: "codex 0.1.0"),
        codexUsageLogReader: TestCodexUsageLogReader(events: []),
        apiClient: SlowCodexRateLimitClient(delayMilliseconds: 500),
        rpcClient: SlowCodexRateLimitClient(delayMilliseconds: 500),
        officialSourceTimeoutSeconds: 0.02
    )
    let service = ProviderMonitorService(adapters: [adapter], providerTimeoutSeconds: 0.5)

    let snapshots = await service.loadProviderSnapshots()

    #expect(snapshots.count == 1)
    #expect(snapshots[0].id == "codex")
    #expect(snapshots[0].health == .error)
    #expect(snapshots[0].metrics.first { $0.id == "refresh-timeout" } == nil)
    #expect(snapshots[0].metrics.first { $0.id == "today-tokens" }?.confidence == .unavailable)
    #expect(snapshots[0].metrics.first { $0.id == "top-model" }?.confidence == .unavailable)
    #expect(snapshots[0].notes.contains { $0.contains("timed out") })
}

@Test func codexProviderAdapterUsesFastOfficialSourceWhenAvailable() async {
    let event = UsageEvent(
        providerID: "codex",
        model: "gpt-5.5 high",
        inputTokens: 3_000,
        outputTokens: 1_000,
        totalTokens: 4_000,
        cachedInputTokens: 2_000,
        uncachedInputTokens: 1_000,
        createdAt: Date(),
        confidence: .observed
    )
    let rateLimits = CodexRateLimitSnapshot(
        primary: CodexRateLimitWindow(
            usedPercent: 25,
            windowMinutes: 300,
            resetsAt: Date().addingTimeInterval(3_600)
        ),
        secondary: nil,
        source: "CLI RPC",
        email: "user@example.com",
        plan: "pro",
        accountPlan: "pro",
        quotaPlan: "prolite",
        resetBank: CodexResetBank(
            entries: [
                CodexResetEntry(
                    id: "reset-1",
                    label: "Full reset (Weekly + 5 hr)",
                    grantedAt: Date().addingTimeInterval(-86_400),
                    expiresAt: Date().addingTimeInterval(7 * 86_400),
                    status: .available,
                    source: "CLI RPC",
                    confidence: .official
                )
            ],
            reportedAvailableCount: 2,
            source: "CLI RPC"
        )
    )
    let adapter = CodexProviderAdapter(
        commandReader: TestLocalCommandReader(output: "codex 0.1.0"),
        codexUsageLogReader: TestCodexUsageLogReader(events: [event]),
        apiClient: FailingCodexRateLimitClient(),
        rpcClient: SuccessfulCodexRateLimitClient(snapshot: rateLimits),
        officialSourceTimeoutSeconds: 0.5
    )

    let snapshot = await adapter.snapshot()

    #expect(snapshot.health == .ready)
    #expect(snapshot.headline == "Synced from CLI RPC")
    #expect(snapshot.bars.first { $0.id == "codex-session" }?.remainingFraction == 0.75)
    #expect(snapshot.metrics.first { $0.id == "source" }?.value == "CLI RPC")
    #expect(snapshot.metrics.first { $0.id == "today-tokens" }?.value == "4.0K")
    #expect(snapshot.metrics.first { $0.id == "today-tokens" }?.subvalue == "Cached input 50.0%")
    #expect(snapshot.metrics.first { $0.id == "today-tokens" }?.confidence == .observed)
    #expect(snapshot.metrics.first { $0.id == "top-model" }?.value == "gpt-5.5 high")
    #expect(snapshot.quotaCreditBank?.availableCount(now: snapshot.updatedAt) == 2)
    #expect(snapshot.quotaCreditBank?.nextExpiry(now: snapshot.updatedAt)?.id == "reset-1")
    #expect(snapshot.activity?.isEmpty == false)
    #expect(snapshot.sourceDiagnostics?.first { $0.id == "codex-cli-rpc" }?.status == .success)
    #expect(snapshot.sourceDiagnostics?.first { $0.id == "codex-oauth-api" }?.status != .success)
}

@Test func codexProviderAdapterRetriesOneTransientOfficialFailure() async {
    let rateLimits = CodexRateLimitSnapshot(
        primary: CodexRateLimitWindow(
            usedPercent: 25,
            windowMinutes: 300,
            resetsAt: Date().addingTimeInterval(3_600)
        ),
        secondary: nil,
        source: "OAuth API"
    )
    let flakyClient = FlakyCodexRateLimitClient(snapshot: rateLimits)
    let adapter = CodexProviderAdapter(
        commandReader: TestLocalCommandReader(output: "codex 0.1.0"),
        codexUsageLogReader: TestCodexUsageLogReader(events: []),
        apiClient: flakyClient,
        rpcClient: FailingCodexRateLimitClient(),
        officialSourceTimeoutSeconds: 0.5,
        officialRetryDelaySeconds: 0
    )

    let snapshot = await adapter.snapshot()

    #expect(flakyClient.fetchCount == 2)
    #expect(snapshot.health == .ready)
    #expect(snapshot.bars.first { $0.id == "codex-session" }?.remainingFraction == 0.75)
    #expect(
        snapshot.sourceDiagnostics?.first { $0.id == "codex-oauth-api" }?.message
            == "Current official quota was returned after one transient retry."
    )
}

@Test func codexProviderAdapterDefaultBudgetAllowsOneCompleteRetry() {
    let longestSourceAttempt = max(
        CodexUsageAPIClient.defaultUsageTimeoutSeconds,
        CodexRPCClient.defaultTimeoutSeconds
    )

    #expect(
        CodexProviderAdapter.defaultOfficialSourceTimeoutSeconds
            >= longestSourceAttempt * 2 + CodexProviderAdapter.defaultOfficialRetryDelaySeconds
    )
}

@Test func codexProviderAdapterWarmsObservedActivityAfterReturningOfficialQuota() async {
    let event = UsageEvent(
        providerID: "codex",
        model: "gpt-5.5 high",
        inputTokens: 3_000,
        outputTokens: 1_000,
        totalTokens: 4_000,
        createdAt: Date(),
        confidence: .observed
    )
    let rateLimits = CodexRateLimitSnapshot(
        primary: CodexRateLimitWindow(
            usedPercent: 25,
            windowMinutes: 300,
            resetsAt: Date().addingTimeInterval(3_600)
        ),
        secondary: nil,
        source: "OAuth API"
    )
    let adapter = CodexProviderAdapter(
        commandReader: TestLocalCommandReader(output: "codex 0.1.0"),
        codexUsageLogReader: BlockingCodexUsageLogReader(blockSeconds: 0.08, events: [event]),
        apiClient: SuccessfulCodexRateLimitClient(snapshot: rateLimits),
        rpcClient: FailingCodexRateLimitClient(),
        officialSourceTimeoutSeconds: 0.5,
        localActivityTimeoutSeconds: 0.01
    )

    let firstSnapshot = await adapter.snapshot()
    try? await Task.sleep(for: .milliseconds(300))
    let warmedSnapshot = await adapter.snapshot()

    #expect(firstSnapshot.health == .ready)
    #expect(firstSnapshot.bars.first { $0.id == "codex-session" }?.remainingFraction == 0.75)
    #expect(firstSnapshot.metrics.first { $0.id == "source" }?.value == "OAuth API")
    #expect(warmedSnapshot.health == .ready)
    #expect(warmedSnapshot.bars.first { $0.id == "codex-session" }?.remainingFraction == 0.75)
    #expect(warmedSnapshot.metrics.first { $0.id == "today-tokens" }?.value == "4.0K")
    #expect(warmedSnapshot.metrics.first { $0.id == "today-tokens" }?.confidence == .observed)
    #expect(warmedSnapshot.activity?.isEmpty == false)
}

@Test func codexProviderAdapterKeepsSlowLocalActivityOutsideOfficialSourceRace() async {
    let event = UsageEvent(
        providerID: "codex",
        model: "gpt-5.5 high",
        inputTokens: 3_000,
        outputTokens: 1_000,
        totalTokens: 4_000,
        createdAt: Date(),
        confidence: .observed
    )
    let rateLimits = CodexRateLimitSnapshot(
        primary: CodexRateLimitWindow(
            usedPercent: 25,
            windowMinutes: 300,
            resetsAt: Date().addingTimeInterval(3_600)
        ),
        secondary: nil,
        source: "OAuth API"
    )
    let usageLogReader = ControlledBlockingCodexUsageLogReader(events: [event])
    defer { usageLogReader.unblock() }
    let adapter = CodexProviderAdapter(
        commandReader: TestLocalCommandReader(output: "codex 0.1.0"),
        codexUsageLogReader: usageLogReader,
        apiClient: DelayedSuccessfulCodexRateLimitClient(
            delayMilliseconds: 50,
            snapshot: rateLimits
        ),
        rpcClient: FailingCodexRateLimitClient(),
        officialSourceTimeoutSeconds: 1,
        localActivityTimeoutSeconds: 0.02
    )
    let service = ProviderMonitorService(adapters: [adapter], providerTimeoutSeconds: 0.5)

    let snapshots = await service.loadProviderSnapshots()

    let snapshot = snapshots.first
    #expect(snapshot?.health == .ready)
    #expect(snapshot?.bars.first?.remainingFraction == 0.75)
    #expect(snapshot?.metrics.first { $0.id == "refresh-timeout" } == nil)
}

@Test func codexProviderAdapterReturnsOfficialSnapshotWithoutWaitingForSlowLocalActivity() async {
    let rateLimits = CodexRateLimitSnapshot(
        primary: CodexRateLimitWindow(
            usedPercent: 25,
            windowMinutes: 300,
            resetsAt: Date().addingTimeInterval(3_600)
        ),
        secondary: nil,
        source: "OAuth API"
    )
    let adapter = CodexProviderAdapter(
        commandReader: TestLocalCommandReader(output: "codex 0.1.0"),
        codexUsageLogReader: BlockingCodexUsageLogReader(blockSeconds: 1),
        apiClient: SuccessfulCodexRateLimitClient(snapshot: rateLimits),
        rpcClient: FailingCodexRateLimitClient(),
        officialSourceTimeoutSeconds: 0.5,
        localActivityTimeoutSeconds: 0.05
    )
    let startedAt = Date()

    let snapshot = await adapter.snapshot()

    #expect(Date().timeIntervalSince(startedAt) < 0.5)
    #expect(snapshot.health == .ready)
    #expect(snapshot.bars.first { $0.id == "codex-session" }?.remainingFraction == 0.75)
    #expect(snapshot.metrics.first { $0.id == "source" }?.value == "OAuth API")
    #expect(snapshot.metrics.first { $0.id == "today-tokens" }?.value == "0")
    #expect(snapshot.metrics.first { $0.id == "today-tokens" }?.confidence == .unavailable)
    #expect(snapshot.metrics.first { $0.id == "30d-tokens" }?.value == "0")
    #expect(snapshot.metrics.first { $0.id == "latest-tokens" }?.value == "0")
    #expect(snapshot.metrics.first { $0.id == "top-model" }?.value == "No requests yet")
    #expect(snapshot.activity?.count == 24)
    #expect(snapshot.notes.contains("Codex local activity scan timed out; observed token metrics are temporarily unavailable."))
}

@Test func codexProviderAdapterReusesRecentLocalActivityAcrossOfficialRefreshes() async {
    let event = UsageEvent(
        providerID: "codex",
        model: "gpt-5.5 high",
        inputTokens: 3_000,
        outputTokens: 1_000,
        totalTokens: 4_000,
        createdAt: Date(),
        confidence: .observed
    )
    let usageLogReader = CountingCodexUsageLogReader(events: [event])
    let rateLimits = CodexRateLimitSnapshot(
        primary: CodexRateLimitWindow(
            usedPercent: 25,
            windowMinutes: 300,
            resetsAt: Date().addingTimeInterval(3_600)
        ),
        secondary: nil,
        source: "OAuth API"
    )
    let adapter = CodexProviderAdapter(
        commandReader: TestLocalCommandReader(output: "codex 0.1.0"),
        codexUsageLogReader: usageLogReader,
        apiClient: SuccessfulCodexRateLimitClient(snapshot: rateLimits),
        rpcClient: FailingCodexRateLimitClient(),
        officialSourceTimeoutSeconds: 0.5,
        localActivityRefreshIntervalSeconds: 300
    )

    let first = await adapter.snapshot()
    let second = await adapter.snapshot()

    #expect(usageLogReader.loadCount == 1)
    #expect(first.metrics.first { $0.id == "today-tokens" }?.value == "4.0K")
    #expect(second.metrics.first { $0.id == "today-tokens" }?.value == "4.0K")
    #expect(second.activity?.isEmpty == false)
    #expect(second.bars.first { $0.id == "codex-session" }?.remainingFraction == 0.75)
}

@Test func codexProviderAdapterKeepsLastCompletedLocalActivityWhenNextScanTimesOut() async {
    let event = UsageEvent(
        providerID: "codex",
        model: "gpt-5.5 high",
        inputTokens: 3_000,
        outputTokens: 1_000,
        totalTokens: 4_000,
        createdAt: Date(),
        confidence: .observed
    )
    let usageLogReader = DelayedAfterFirstCodexUsageLogReader(
        delaySeconds: 0.25,
        events: [event]
    )
    let rateLimits = CodexRateLimitSnapshot(
        primary: CodexRateLimitWindow(
            usedPercent: 25,
            windowMinutes: 300,
            resetsAt: Date().addingTimeInterval(3_600)
        ),
        secondary: nil,
        source: "OAuth API"
    )
    let adapter = CodexProviderAdapter(
        commandReader: TestLocalCommandReader(output: "codex 0.1.0"),
        codexUsageLogReader: usageLogReader,
        apiClient: SuccessfulCodexRateLimitClient(snapshot: rateLimits),
        rpcClient: FailingCodexRateLimitClient(),
        officialSourceTimeoutSeconds: 0.5,
        localActivityTimeoutSeconds: 0.02,
        localActivityRefreshIntervalSeconds: 0
    )

    _ = await adapter.snapshot()
    let timedOut = await adapter.snapshot()

    #expect(timedOut.metrics.first { $0.id == "today-tokens" }?.value == "4.0K")
    #expect(timedOut.metrics.first { $0.id == "today-tokens" }?.confidence == .observed)
    #expect(timedOut.activity?.isEmpty == false)
    #expect(timedOut.notes.contains("Codex local activity scan timed out; observed token metrics are temporarily unavailable."))
    #expect(timedOut.bars.first { $0.id == "codex-session" }?.remainingFraction == 0.75)
}

@Test func codexProviderAdapterReturnsOfficialErrorWithoutWaitingForSlowLocalActivity() async {
    let adapter = CodexProviderAdapter(
        commandReader: TestLocalCommandReader(output: "codex 0.1.0"),
        codexUsageLogReader: BlockingCodexUsageLogReader(blockSeconds: 1),
        apiClient: FailingCodexRateLimitClient(),
        rpcClient: FailingCodexRateLimitClient(),
        officialSourceTimeoutSeconds: 0.5,
        localActivityTimeoutSeconds: 0.05,
        officialFailureLocalActivityTimeoutSeconds: 0.05
    )
    let startedAt = Date()

    let snapshot = await adapter.snapshot()

    #expect(Date().timeIntervalSince(startedAt) < 0.5)
    #expect(snapshot.health == .error)
    #expect(snapshot.bars.isEmpty)
    #expect(snapshot.metrics.first { $0.id == "official-sync" }?.value == "Failed")
    #expect(snapshot.metrics.first { $0.id == "today-tokens" }?.value == "0")
    #expect(snapshot.metrics.first { $0.id == "today-tokens" }?.confidence == .unavailable)
    #expect(snapshot.metrics.first { $0.id == "top-model" }?.value == "No requests yet")
    #expect(snapshot.activity?.count == 24)
    #expect(snapshot.notes.contains("Codex local activity scan timed out; observed token metrics are temporarily unavailable."))
}

@Test func codexProviderAdapterReportsOfficialFailureDiagnostics() async throws {
    let adapter = CodexProviderAdapter(
        commandReader: TestLocalCommandReader(output: "codex 0.1.0"),
        codexUsageLogReader: TestCodexUsageLogReader(events: []),
        apiClient: FailingCodexRateLimitClient(),
        rpcClient: FailingCodexRateLimitClient(),
        officialSourceTimeoutSeconds: 0.5
    )

    let snapshot = await adapter.snapshot()

    #expect(snapshot.health == .error)
    #expect(snapshot.bars.isEmpty)
    #expect(snapshot.notes.first == "Official Codex usage is unavailable.")
    #expect(snapshot.notes.prefix(4).contains("OAuth API sync failed: unavailable"))
    #expect(snapshot.notes.prefix(4).contains("CLI RPC sync failed: unavailable"))
    #expect(snapshot.sourceDiagnostics?.count == 2)
    #expect(snapshot.sourceDiagnostics?.allSatisfy { $0.status == .failure } == true)
}

@Test func codexProviderAdapterAddsObservedActivityMetricsWhenOfficialSourcesFail() async {
    let event = UsageEvent(
        providerID: "codex",
        model: "gpt-5.5 high",
        inputTokens: 3_000,
        outputTokens: 1_000,
        totalTokens: 4_000,
        createdAt: Date(),
        confidence: .observed
    )
    let adapter = CodexProviderAdapter(
        commandReader: TestLocalCommandReader(output: "codex 0.1.0"),
        codexUsageLogReader: TestCodexUsageLogReader(events: [event]),
        apiClient: FailingCodexRateLimitClient(),
        rpcClient: FailingCodexRateLimitClient(),
        officialSourceTimeoutSeconds: 0.5
    )

    let snapshot = await adapter.snapshot()

    #expect(snapshot.health == .error)
    #expect(snapshot.bars.isEmpty)
    #expect(snapshot.metrics.first { $0.id == "today-tokens" }?.value == "4.0K")
    #expect(snapshot.metrics.first { $0.id == "today-tokens" }?.confidence == .observed)
    #expect(snapshot.metrics.first { $0.id == "top-model" }?.value == "gpt-5.5 high")
    #expect(snapshot.notes.contains("Official Codex usage is unavailable."))
}

private struct TestLocalCommandReader: LocalCommandReading {
    let output: String?

    func firstSuccessfulOutput(commands: [[String]]) -> String? {
        output
    }
}

private struct TestCodexUsageLogReader: CodexUsageLogReading {
    let events: [UsageEvent]

    func loadEvents() -> [UsageEvent] {
        events
    }
}

private struct BlockingCodexUsageLogReader: CodexUsageLogReading {
    let blockSeconds: TimeInterval
    var events: [UsageEvent] = []

    func loadEvents() -> [UsageEvent] {
        Thread.sleep(forTimeInterval: blockSeconds)
        return events
    }
}

private final class ControlledBlockingCodexUsageLogReader: CodexUsageLogReading, @unchecked Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let events: [UsageEvent]

    init(events: [UsageEvent]) {
        self.events = events
    }

    func loadEvents() -> [UsageEvent] {
        semaphore.wait()
        return events
    }

    func unblock() {
        semaphore.signal()
    }
}

private final class CountingCodexUsageLogReader: CodexUsageLogReading, @unchecked Sendable {
    private let lock = NSLock()
    private let events: [UsageEvent]
    private var storedLoadCount = 0

    init(events: [UsageEvent]) {
        self.events = events
    }

    var loadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedLoadCount
    }

    func loadEvents() -> [UsageEvent] {
        lock.lock()
        storedLoadCount += 1
        lock.unlock()
        return events
    }
}

private final class DelayedAfterFirstCodexUsageLogReader: CodexUsageLogReading, @unchecked Sendable {
    private let lock = NSLock()
    private let delaySeconds: TimeInterval
    private let events: [UsageEvent]
    private var loadCount = 0

    init(delaySeconds: TimeInterval, events: [UsageEvent]) {
        self.delaySeconds = delaySeconds
        self.events = events
    }

    func loadEvents() -> [UsageEvent] {
        lock.lock()
        loadCount += 1
        let shouldDelay = loadCount > 1
        lock.unlock()

        if shouldDelay {
            Thread.sleep(forTimeInterval: delaySeconds)
        }
        return events
    }
}

private struct SlowCodexRateLimitClient: CodexRateLimitSnapshotFetching {
    let delayMilliseconds: Int

    func fetchSnapshot() async throws -> CodexRateLimitSnapshot {
        try await Task.sleep(for: .milliseconds(delayMilliseconds))
        throw TestCodexProviderAdapterError.unavailable
    }
}

private struct FailingCodexRateLimitClient: CodexRateLimitSnapshotFetching {
    func fetchSnapshot() async throws -> CodexRateLimitSnapshot {
        throw TestCodexProviderAdapterError.unavailable
    }
}

private struct SuccessfulCodexRateLimitClient: CodexRateLimitSnapshotFetching {
    let snapshot: CodexRateLimitSnapshot

    func fetchSnapshot() async throws -> CodexRateLimitSnapshot {
        snapshot
    }
}

private struct DelayedSuccessfulCodexRateLimitClient: CodexRateLimitSnapshotFetching {
    let delayMilliseconds: Int
    let snapshot: CodexRateLimitSnapshot

    func fetchSnapshot() async throws -> CodexRateLimitSnapshot {
        try await Task.sleep(for: .milliseconds(delayMilliseconds))
        return snapshot
    }
}

private final class FlakyCodexRateLimitClient: CodexRateLimitSnapshotFetching, @unchecked Sendable {
    private let lock = NSLock()
    private let snapshot: CodexRateLimitSnapshot
    private var storedFetchCount = 0

    init(snapshot: CodexRateLimitSnapshot) {
        self.snapshot = snapshot
    }

    var fetchCount: Int {
        lock.withLock { storedFetchCount }
    }

    func fetchSnapshot() async throws -> CodexRateLimitSnapshot {
        let attempt = lock.withLock {
            storedFetchCount += 1
            return storedFetchCount
        }

        if attempt == 1 {
            throw URLError(.timedOut)
        }
        return snapshot
    }
}

private enum TestCodexProviderAdapterError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "unavailable"
    }
}
