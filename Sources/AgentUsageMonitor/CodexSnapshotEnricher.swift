import AgentUsageCore
import Foundation

struct CodexSnapshotEnricher: Sendable {
    private let usageLogReader: any CodexUsageLogReading
    private let actions: [ProviderAction]
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    init(
        usageLogReader: any CodexUsageLogReading,
        actions: [ProviderAction],
        now: @escaping @Sendable () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.usageLogReader = usageLogReader
        self.actions = actions
        self.now = now
        self.calendar = calendar
    }

    func enriched(_ snapshot: ProviderSnapshot, extraNotes: [String]) -> ProviderSnapshot {
        let events = usageLogReader.loadEvents()
        return enriched(snapshot, events: events, extraNotes: extraNotes)
    }

    func enriched(
        _ snapshot: ProviderSnapshot,
        events: [UsageEvent],
        extraNotes: [String]
    ) -> ProviderSnapshot {
        let currentDate = now()
        let eligibleEvents = events.filter { $0.createdAt <= currentDate }
        let startOfToday = calendar.startOfDay(for: currentDate)
        let thirtyDaysAgo = currentDate.addingTimeInterval(-30 * 24 * 3_600)
        let todayEvents = eligibleEvents.filter { $0.createdAt >= startOfToday }
        let thirtyDayEvents = eligibleEvents.filter { $0.createdAt >= thirtyDaysAgo }
        let latestEvent = eligibleEvents.max { $0.createdAt < $1.createdAt }
        let summary = UsageSummarizer.summarize(
            events: eligibleEvents,
            now: currentDate,
            calendar: calendar,
            accounting: .reportedTotal
        )
        let activity = UsageActivitySummarizer.todayHourlyBuckets(
            events: eligibleEvents,
            now: currentDate,
            calendar: calendar,
            accounting: .reportedTotal
        )
        let usageMetricIDs = Set(Self.usageMetricIDs)
        let metrics = snapshot.metrics.filter { usageMetricIDs.contains($0.id) == false }
            + codexUsageMetrics(
                from: summary,
                todayEvents: todayEvents,
                thirtyDayEvents: thirtyDayEvents,
                latestEvent: latestEvent
            )

        return ProviderSnapshot(
            id: snapshot.id,
            name: snapshot.name,
            kind: snapshot.kind,
            updatedAt: snapshot.updatedAt,
            health: snapshot.health,
            headline: snapshot.headline,
            metrics: metrics,
            bars: snapshot.bars,
            quotaCreditBank: snapshot.quotaCreditBank,
            activity: activity,
            accounts: snapshot.accounts,
            sourceDiagnostics: snapshot.sourceDiagnostics,
            notes: deduplicatedNotes(snapshot.notes + extraNotes + [
                "Local token cards and activity use reported total_tokens, including cached input; replay and duplicate telemetry rows are filtered."
            ]),
            actions: actions
        )
    }

    private static let usageMetricIDs = ["today-tokens", "30d-tokens", "latest-tokens", "top-model"]

    private func codexUsageMetrics(
        from summary: UsageSummary,
        todayEvents: [UsageEvent],
        thirtyDayEvents: [UsageEvent],
        latestEvent: UsageEvent?
    ) -> [UsageMetric] {
        [
            UsageMetric(
                id: "today-tokens",
                label: "Today local tokens",
                value: UsageValueFormatter.tokens(summary.todayTokens),
                subvalue: cachedInputShare(for: todayEvents),
                detail: tokenDetail,
                confidence: todayEvents.isEmpty ? .unavailable : .observed
            ),
            UsageMetric(
                id: "30d-tokens",
                label: "30d local tokens",
                value: UsageValueFormatter.tokens(summary.thirtyDayTokens),
                subvalue: cachedInputShare(for: thirtyDayEvents),
                detail: tokenDetail,
                confidence: thirtyDayEvents.isEmpty ? .unavailable : .observed
            ),
            UsageMetric(
                id: "latest-tokens",
                label: "Latest local tokens",
                value: UsageValueFormatter.tokens(summary.latestTokens),
                subvalue: latestEvent.flatMap { cachedInputShare(for: [$0]) },
                detail: tokenDetail,
                confidence: latestEvent == nil ? .unavailable : .observed
            ),
            UsageMetric(
                id: "top-model",
                label: "Top local model",
                value: summary.topModel,
                detail: "By observed reported total_tokens",
                confidence: summary.topModel == "No requests yet" ? .unavailable : .observed
            )
        ]
    }

    private func cachedInputShare(for events: [UsageEvent]) -> String? {
        let totalTokens = events.reduce(0) { $0 + max(0, $1.totalTokens) }
        guard totalTokens > 0 else {
            return nil
        }

        let cachedInputTokens = events.reduce(0) { total, event in
            let boundedCachedInput = min(
                max(0, event.cachedInputTokens ?? 0),
                max(0, event.inputTokens)
            )
            return total + boundedCachedInput
        }
        let percentage = Double(cachedInputTokens) / Double(totalTokens) * 100
        return "Cached input \(String(format: "%.1f%%", percentage))"
    }

    private var tokenDetail: String {
        "Observed total_tokens from local Codex logs, including cached input. Duplicate cumulative rows and forked-session replay are filtered. This is local telemetry, not an official dashboard total or billing amount."
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
}
