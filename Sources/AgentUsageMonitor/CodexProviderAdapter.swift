import AgentUsageCore
import Foundation

struct CodexProviderAdapter: ProviderSnapshotAdapter, @unchecked Sendable {
    static let defaultOfficialSourceTimeoutSeconds: TimeInterval = 20
    static let defaultOfficialRetryDelaySeconds: TimeInterval = 0.5
    static let defaultLocalActivityTimeoutSeconds: TimeInterval = 1
    static let defaultOfficialFailureLocalActivityTimeoutSeconds: TimeInterval = 1
    static let defaultLocalActivityRefreshIntervalSeconds: TimeInterval = 5 * 60

    let registration = ProviderRegistration.codex

    private let commandReader: any LocalCommandReading
    private let codexUsageLogReader: any CodexUsageLogReading
    private let apiClient: any CodexRateLimitSnapshotFetching
    private let rpcClient: any CodexRateLimitSnapshotFetching
    private let officialSourceTimeoutSeconds: TimeInterval
    private let officialRetryDelaySeconds: TimeInterval
    private let localActivityTimeoutSeconds: TimeInterval
    private let officialFailureLocalActivityTimeoutSeconds: TimeInterval
    private let localActivityRefreshIntervalSeconds: TimeInterval
    private let localActivityCache: CodexLocalActivityCache

    init(
        commandReader: any LocalCommandReading = LocalCommandReader(),
        codexUsageLogReader: any CodexUsageLogReading = CodexUsageLogReader(),
        apiClient: any CodexRateLimitSnapshotFetching = CodexUsageAPIClient(),
        rpcClient: any CodexRateLimitSnapshotFetching = CodexRPCClient(),
        officialSourceTimeoutSeconds: TimeInterval = Self.defaultOfficialSourceTimeoutSeconds,
        officialRetryDelaySeconds: TimeInterval = Self.defaultOfficialRetryDelaySeconds,
        localActivityTimeoutSeconds: TimeInterval = Self.defaultLocalActivityTimeoutSeconds,
        officialFailureLocalActivityTimeoutSeconds: TimeInterval = Self.defaultOfficialFailureLocalActivityTimeoutSeconds,
        localActivityRefreshIntervalSeconds: TimeInterval = Self.defaultLocalActivityRefreshIntervalSeconds
    ) {
        self.commandReader = commandReader
        self.codexUsageLogReader = codexUsageLogReader
        self.apiClient = apiClient
        self.rpcClient = rpcClient
        self.officialSourceTimeoutSeconds = officialSourceTimeoutSeconds
        self.officialRetryDelaySeconds = officialRetryDelaySeconds
        self.localActivityTimeoutSeconds = localActivityTimeoutSeconds
        self.officialFailureLocalActivityTimeoutSeconds = officialFailureLocalActivityTimeoutSeconds
        self.localActivityRefreshIntervalSeconds = localActivityRefreshIntervalSeconds
        self.localActivityCache = CodexLocalActivityCache()
    }

    func snapshot() async -> ProviderSnapshot {
        let commandReader = commandReader
        let codexVersionTask = Task.detached(priority: .utility) {
            commandReader.firstSuccessfulOutput(commands: [
                ["codex", "--version"],
                ["codex", "-V"]
            ])
        }
        let officialSync = await officialRateLimitSnapshot()
        let codexVersion = await codexVersionTask.value
        // Keep large local log scans away from the latency-sensitive official source race.
        let localActivityScan = startedLocalActivityScanIfNeeded()
        let cliNote = codexVersion.map { "Codex CLI detected: \($0)" } ?? "Codex CLI was not found on PATH."
        let sourceNotes = [cliNote] + officialSync.notes

        if let rateLimits = officialSync.snapshot {
            var snapshot = CodexRateLimitSnapshotFactory.providerSnapshot(from: rateLimits)
                .replacingSourceDiagnostics(officialSync.diagnostics)
            snapshot = await snapshotWithCodexActions(
                snapshot,
                extraNotes: sourceNotes,
                timeoutSeconds: localActivityTimeoutSeconds,
                localActivityScan: localActivityScan
            )
            return snapshot
        }

        let errorSnapshot = ProviderSnapshot(
            id: "codex",
            name: "Codex",
            kind: .subscription,
            health: .error,
            headline: "Official Codex usage unavailable",
            metrics: [
                UsageMetric(
                    id: "official-sync",
                    label: "Official sync",
                    value: "Failed",
                    detail: "OAuth API and CLI RPC did not return Codex rate-limit windows.",
                    confidence: .unavailable
                )
            ],
            bars: [],
            sourceDiagnostics: officialSync.diagnostics,
            notes: [
                "Official Codex usage is unavailable.",
                "Cached snapshots are not shown as Codex quota; local token activity is labeled Observed."
            ] + officialSync.notes + [cliNote],
            actions: codexActions
        )
        return await snapshotWithCodexActions(
            errorSnapshot,
            extraNotes: [],
            timeoutSeconds: officialFailureLocalActivityTimeoutSeconds,
            localActivityScan: localActivityScan
        )
    }

    private func startedLocalActivityScanIfNeeded() -> CodexLocalActivityScan? {
        guard localActivityCache.freshPayload(
            maxAge: localActivityRefreshIntervalSeconds
        ) == nil else {
            return nil
        }

        let usageLogReader = codexUsageLogReader
        return CodexLocalActivityScan(
            startedAtUptime: ProcessInfo.processInfo.systemUptime,
            task: Task.detached(priority: .utility) {
                usageLogReader.loadEvents()
            }
        )
    }

    private var codexActions: [ProviderAction] {
        [
            ProviderAction(
                id: "codex-web-sync",
                title: "Open Codex Web Debug",
                url: nil
            ),
            ProviderAction(
                id: "codex-docs",
                title: "Open Codex Pricing Docs",
                url: URL(string: "https://developers.openai.com/codex/pricing")
            )
        ]
    }

    private func snapshotWithCodexActions(
        _ snapshot: ProviderSnapshot,
        extraNotes: [String],
        timeoutSeconds: TimeInterval,
        localActivityScan: CodexLocalActivityScan?
    ) async -> ProviderSnapshot {
        let snapshotWithEmptyLocalActivity = timeoutFallbackSnapshot(
            snapshot,
            extraNotes: extraNotes
        )
        if let cachedActivity = localActivityCache.freshPayload(
            maxAge: localActivityRefreshIntervalSeconds
        ) {
            return cachedActivity.applying(to: snapshotWithEmptyLocalActivity)
        }

        let timeoutFallback = timeoutFallbackSnapshot(
            snapshot,
            extraNotes: extraNotes + [
                "Codex local activity scan timed out; observed token metrics are temporarily unavailable."
            ]
        )

        return await withCheckedContinuation { continuation in
            let raceBox = CodexEnrichmentRaceBox()
            let usageLogReader = codexUsageLogReader
            let actions = codexActions
            let localActivityCache = localActivityCache
            let remainingTimeoutSeconds = localActivityScan.map { scan in
                let elapsed = max(0, ProcessInfo.processInfo.systemUptime - scan.startedAtUptime)
                return max(0, timeoutSeconds - elapsed)
            } ?? timeoutSeconds

            let enrichmentTask = Task.detached(priority: .utility) {
                let enricher = CodexSnapshotEnricher(
                    usageLogReader: usageLogReader,
                    actions: actions
                )
                let enriched: ProviderSnapshot
                if let localActivityScan {
                    let events = await localActivityScan.task.value
                    enriched = enricher.enriched(
                        snapshot,
                        events: events,
                        extraNotes: extraNotes
                    )
                } else {
                    enriched = enricher.enriched(snapshot, extraNotes: extraNotes)
                }
                localActivityCache.store(enriched)
                raceBox.resumeOnce(continuation, returning: enriched, winner: .enrichment)
            }

            let timeoutTask = Task.detached(priority: .utility) {
                try? await Task.sleep(for: .seconds(remainingTimeoutSeconds))
                let fallback = localActivityCache.latestPayload()?.applying(to: timeoutFallback)
                    ?? timeoutFallback
                raceBox.resumeOnce(continuation, returning: fallback, winner: .timeout)
            }

            raceBox.setTasks(enrichmentTask: enrichmentTask, timeoutTask: timeoutTask)
        }
    }

    private func snapshotWithActions(_ snapshot: ProviderSnapshot, extraNotes: [String]) -> ProviderSnapshot {
        ProviderSnapshot(
            id: snapshot.id,
            name: snapshot.name,
            kind: snapshot.kind,
            updatedAt: snapshot.updatedAt,
            health: snapshot.health,
            headline: snapshot.headline,
            metrics: snapshot.metrics,
            bars: snapshot.bars,
            quotaCreditBank: snapshot.quotaCreditBank,
            activity: snapshot.activity,
            accounts: snapshot.accounts,
            sourceDiagnostics: snapshot.sourceDiagnostics,
            notes: deduplicatedNotes(snapshot.notes + extraNotes),
            actions: codexActions
        )
    }

    private func timeoutFallbackSnapshot(_ snapshot: ProviderSnapshot, extraNotes: [String]) -> ProviderSnapshot {
        CodexSnapshotEnricher(
            usageLogReader: EmptyCodexUsageLogReader(),
            actions: codexActions
        ).enriched(snapshot, extraNotes: extraNotes)
    }

    private func deduplicatedNotes(_ notes: [String]) -> [String] {
        var seen = Set<String>()
        var uniqueNotes: [String] = []

        for note in notes {
            if seen.insert(note).inserted {
                uniqueNotes.append(note)
            }
        }

        return uniqueNotes
    }

    private func officialRateLimitSnapshot() async -> (
        snapshot: CodexRateLimitSnapshot?,
        notes: [String],
        diagnostics: [ProviderSourceDiagnostic]
    ) {
        let sources = [
            CodexOfficialSource(id: "codex-oauth-api", name: "OAuth API"),
            CodexOfficialSource(id: "codex-cli-rpc", name: "CLI RPC")
        ]
        let attemptedAt = Date()

        return await withTaskGroup(of: CodexOfficialSyncResult.self) { group -> (
            snapshot: CodexRateLimitSnapshot?,
            notes: [String],
            diagnostics: [ProviderSourceDiagnostic]
        ) in
            group.addTask {
                await fetchOfficialSnapshot(
                    source: sources[0],
                    client: apiClient
                )
            }
            group.addTask {
                await fetchOfficialSnapshot(
                    source: sources[1],
                    client: rpcClient
                )
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(officialSourceTimeoutSeconds))
                return .timedOut(officialSourceTimeoutSeconds, Date())
            }

            var failureNotes: [String] = []
            var completedSourceIDs = Set<String>()
            var diagnosticsByID: [String: ProviderSourceDiagnostic] = [:]

            while let result = await group.next() {
                switch result {
                case .success(let source, let snapshot, let completedAt, let recoveredAfterRetry):
                    completedSourceIDs.insert(source.id)
                    diagnosticsByID[source.id] = ProviderSourceDiagnostic(
                        id: source.id,
                        name: source.name,
                        confidence: .official,
                        status: .success,
                        attemptedAt: attemptedAt,
                        lastSuccessAt: completedAt,
                        message: recoveredAfterRetry
                            ? "Current official quota was returned after one transient retry."
                            : "Current official quota was returned successfully."
                    )
                    for pendingSource in sources where completedSourceIDs.contains(pendingSource.id) == false {
                        diagnosticsByID[pendingSource.id] = ProviderSourceDiagnostic(
                            id: pendingSource.id,
                            name: pendingSource.name,
                            confidence: .official,
                            status: .cancelled,
                            attemptedAt: attemptedAt,
                            message: "No completed result was needed after another official source succeeded."
                        )
                    }
                    group.cancelAll()
                    return (
                        snapshot,
                        failureNotes,
                        orderedDiagnostics(sources: sources, values: diagnosticsByID)
                    )
                case .failure(let source, let note, let completedAt):
                    completedSourceIDs.insert(source.id)
                    failureNotes.append(note)
                    diagnosticsByID[source.id] = ProviderSourceDiagnostic(
                        id: source.id,
                        name: source.name,
                        confidence: .official,
                        status: .failure,
                        attemptedAt: attemptedAt,
                        lastFailureAt: completedAt,
                        message: note
                    )
                    if completedSourceIDs.count == sources.count {
                        group.cancelAll()
                        return (
                            nil,
                            failureNotes,
                            orderedDiagnostics(sources: sources, values: diagnosticsByID)
                        )
                    }
                case .timedOut(let timeoutSeconds, let completedAt):
                    group.cancelAll()
                    failureNotes.append("Official Codex sync timed out after \(formattedSeconds(timeoutSeconds)).")
                    for source in sources where completedSourceIDs.contains(source.id) == false {
                        diagnosticsByID[source.id] = ProviderSourceDiagnostic(
                            id: source.id,
                            name: source.name,
                            confidence: .official,
                            status: .failure,
                            attemptedAt: attemptedAt,
                            lastFailureAt: completedAt,
                            message: "Timed out before this source returned current official quota."
                        )
                    }
                    return (
                        nil,
                        failureNotes,
                        orderedDiagnostics(sources: sources, values: diagnosticsByID)
                    )
                }
            }

            return (
                nil,
                failureNotes,
                orderedDiagnostics(sources: sources, values: diagnosticsByID)
            )
        }
    }

    private func fetchOfficialSnapshot(
        source: CodexOfficialSource,
        client: any CodexRateLimitSnapshotFetching
    ) async -> CodexOfficialSyncResult {
        var attempt = 1

        while true {
            do {
                return .success(
                    source,
                    try await client.fetchSnapshot(),
                    Date(),
                    attempt > 1
                )
            } catch is CancellationError {
                return .failure(source, "\(source.name) sync was cancelled.", Date())
            } catch {
                guard attempt == 1, shouldRetryOfficialSource(after: error) else {
                    let retrySuffix = attempt > 1 ? " after one transient retry" : ""
                    return .failure(
                        source,
                        "\(source.name) sync failed\(retrySuffix): \(error.localizedDescription)",
                        Date()
                    )
                }

                attempt += 1
                do {
                    try await Task.sleep(for: .seconds(officialRetryDelaySeconds))
                } catch {
                    return .failure(source, "\(source.name) sync was cancelled.", Date())
                }
            }
        }
    }

    private func shouldRetryOfficialSource(after error: Error) -> Bool {
        if let urlError = error as? URLError {
            return urlError.isTransientCodexSourceFailure
        }
        if let apiError = error as? CodexUsageAPIError {
            return apiError.isTransient
        }
        if let rpcError = error as? CodexRPCError {
            return rpcError.isTransient
        }
        return false
    }

    private func orderedDiagnostics(
        sources: [CodexOfficialSource],
        values: [String: ProviderSourceDiagnostic]
    ) -> [ProviderSourceDiagnostic] {
        sources.map { source in
            values[source.id] ?? ProviderSourceDiagnostic(
                id: source.id,
                name: source.name,
                confidence: .official,
                status: .notAttempted,
                message: "This source did not produce a completed result."
            )
        }
    }

    private func formattedSeconds(_ seconds: TimeInterval) -> String {
        if seconds.rounded() == seconds {
            return "\(Int(seconds))s"
        }
        return String(format: "%.2fs", seconds)
    }
}

private struct CodexLocalActivityScan: Sendable {
    let startedAtUptime: TimeInterval
    let task: Task<[UsageEvent], Never>
}

private struct CodexLocalActivityPayload: Sendable {
    static let metricIDs: Set<String> = ["today-tokens", "30d-tokens", "latest-tokens", "top-model"]

    let metrics: [UsageMetric]
    let activity: [UsageActivityBucket]?
    let capturedAt: Date

    func applying(to snapshot: ProviderSnapshot) -> ProviderSnapshot {
        ProviderSnapshot(
            id: snapshot.id,
            name: snapshot.name,
            kind: snapshot.kind,
            updatedAt: snapshot.updatedAt,
            health: snapshot.health,
            headline: snapshot.headline,
            metrics: snapshot.metrics.filter { Self.metricIDs.contains($0.id) == false } + metrics,
            bars: snapshot.bars,
            quotaCreditBank: snapshot.quotaCreditBank,
            activity: activity,
            accounts: snapshot.accounts,
            sourceDiagnostics: snapshot.sourceDiagnostics,
            notes: snapshot.notes,
            actions: snapshot.actions
        )
    }
}

private final class CodexLocalActivityCache: @unchecked Sendable {
    private let lock = NSLock()
    private var payload: CodexLocalActivityPayload?

    func store(_ snapshot: ProviderSnapshot, now: Date = Date()) {
        let metrics = snapshot.metrics.filter { CodexLocalActivityPayload.metricIDs.contains($0.id) }
        guard metrics.isEmpty == false || snapshot.activity != nil else {
            return
        }

        lock.lock()
        payload = CodexLocalActivityPayload(
            metrics: metrics,
            activity: snapshot.activity,
            capturedAt: now
        )
        lock.unlock()
    }

    func freshPayload(maxAge: TimeInterval, now: Date = Date()) -> CodexLocalActivityPayload? {
        guard maxAge > 0, let payload = latestPayload() else {
            return nil
        }
        return now.timeIntervalSince(payload.capturedAt) < maxAge ? payload : nil
    }

    func latestPayload() -> CodexLocalActivityPayload? {
        lock.lock()
        defer { lock.unlock() }
        return payload
    }
}

private struct EmptyCodexUsageLogReader: CodexUsageLogReading {
    func loadEvents() -> [UsageEvent] {
        []
    }
}

private enum CodexOfficialSyncResult: Sendable {
    case success(CodexOfficialSource, CodexRateLimitSnapshot, Date, Bool)
    case failure(CodexOfficialSource, String, Date)
    case timedOut(TimeInterval, Date)
}

private struct CodexOfficialSource: Sendable {
    let id: String
    let name: String
}

private final class CodexEnrichmentRaceBox: @unchecked Sendable {
    enum Winner {
        case enrichment
        case timeout
    }

    private let lock = NSLock()
    private var winner: Winner?
    private var enrichmentTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    func setTasks(enrichmentTask: Task<Void, Never>, timeoutTask: Task<Void, Never>) {
        let taskToCancel: Task<Void, Never>?

        lock.lock()
        self.enrichmentTask = enrichmentTask
        self.timeoutTask = timeoutTask
        taskToCancel = taskToCancelAfterLock()
        lock.unlock()

        taskToCancel?.cancel()
    }

    func resumeOnce(
        _ continuation: CheckedContinuation<ProviderSnapshot, Never>,
        returning snapshot: ProviderSnapshot,
        winner: Winner
    ) {
        let taskToCancel: Task<Void, Never>?

        lock.lock()
        guard self.winner == nil else {
            lock.unlock()
            return
        }

        self.winner = winner
        taskToCancel = taskToCancelAfterLock()
        lock.unlock()

        taskToCancel?.cancel()
        continuation.resume(returning: snapshot)
    }

    private func taskToCancelAfterLock() -> Task<Void, Never>? {
        switch winner {
        case .enrichment:
            return timeoutTask
        case .timeout:
            return enrichmentTask
        case nil:
            return nil
        }
    }
}
