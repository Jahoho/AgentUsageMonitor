import AgentUsageCore
import Foundation
import Testing
@testable import AgentUsageMonitor

@Test func codexSnapshotEnricherDoesNotDuplicateUsageMetrics() {
    let event = UsageEvent(
        providerID: "codex",
        model: "codex",
        inputTokens: 4_000,
        outputTokens: 1_000,
        totalTokens: 5_000,
        createdAt: Date(),
        confidence: .observed
    )
    let enricher = CodexSnapshotEnricher(
        usageLogReader: TestCodexUsageLogReader(events: [event]),
        actions: []
    )

    let once = enricher.enriched(baseCodexSnapshot(), extraNotes: [])
    let twice = enricher.enriched(once, extraNotes: [])

    #expect(twice.metrics.filter { $0.id == "today-tokens" }.count == 1)
    #expect(twice.metrics.filter { $0.id == "30d-tokens" }.count == 1)
    #expect(twice.metrics.first { $0.id == "latest-tokens" }?.value == "5.0K")
}

@Test func codexSnapshotEnricherShowsRealTopModelFromUsageEvents() {
    let events = [
        UsageEvent(
            providerID: "codex",
            model: "codex",
            inputTokens: 500,
            outputTokens: 500,
            totalTokens: 1_000,
            createdAt: Date(),
            confidence: .observed
        ),
        UsageEvent(
            providerID: "codex",
            model: "gpt-5.5 high",
            inputTokens: 4_000,
            outputTokens: 2_000,
            totalTokens: 6_000,
            createdAt: Date(),
            confidence: .observed
        )
    ]
    let enricher = CodexSnapshotEnricher(
        usageLogReader: TestCodexUsageLogReader(events: events),
        actions: []
    )

    let snapshot = enricher.enriched(baseCodexSnapshot(), extraNotes: [])

    #expect(snapshot.metrics.first { $0.id == "top-model" }?.value == "gpt-5.5 high")
}

@Test func codexSnapshotEnricherKeepsUsageMetricSlotsWhenNoEventsExist() {
    let enricher = CodexSnapshotEnricher(
        usageLogReader: TestCodexUsageLogReader(events: []),
        actions: []
    )

    let snapshot = enricher.enriched(baseCodexSnapshot(), extraNotes: [])

    #expect(snapshot.metrics.first { $0.id == "today-tokens" }?.value == "0")
    #expect(snapshot.metrics.first { $0.id == "today-tokens" }?.confidence == .unavailable)
    #expect(snapshot.metrics.first { $0.id == "30d-tokens" }?.value == "0")
    #expect(snapshot.metrics.first { $0.id == "latest-tokens" }?.value == "0")
    #expect(snapshot.metrics.first { $0.id == "top-model" }?.value == "No requests yet")
    #expect(snapshot.metrics.first { $0.id == "top-model" }?.confidence == .unavailable)
    #expect(snapshot.activity?.count == 24)
}

@Test func codexSnapshotEnricherShowsCachedInputShareOnTokenMetrics() {
    let now = Date(timeIntervalSince1970: 1_704_067_200)
    let events = [
        UsageEvent(
        providerID: "codex",
        model: "gpt-5.5 high",
        inputTokens: 100_000,
        outputTokens: 100_000,
        totalTokens: 200_000,
        cachedInputTokens: 0,
        uncachedInputTokens: 100_000,
            createdAt: now,
            confidence: .observed
        )
    ]
    let enricher = CodexSnapshotEnricher(
        usageLogReader: TestCodexUsageLogReader(events: events),
        actions: [],
        now: { now },
        calendar: Calendar(identifier: .gregorian)
    )

    let snapshot = enricher.enriched(baseCodexSnapshot(), extraNotes: [])

    #expect(snapshot.metrics.first { $0.id == "today-tokens" }?.subvalue == "Cached input 0.0%")
    #expect(snapshot.metrics.first { $0.id == "30d-tokens" }?.subvalue == "Cached input 0.0%")
    #expect(snapshot.metrics.first { $0.id == "latest-tokens" }?.subvalue == "Cached input 0.0%")
    #expect(snapshot.metrics.first { $0.id == "today-tokens" }?.detail.contains("not an official dashboard total") == true)
}

@Test func codexSnapshotEnricherFormatsSmallCachedInputShare() {
    let now = Date(timeIntervalSince1970: 1_704_067_200)
    let event = UsageEvent(
        providerID: "codex",
        model: "gpt-5.6-luna",
        inputTokens: 100,
        outputTokens: 100,
        totalTokens: 200,
        cachedInputTokens: 0,
        uncachedInputTokens: 100,
        createdAt: now,
        confidence: .observed
    )
    let enricher = CodexSnapshotEnricher(
        usageLogReader: TestCodexUsageLogReader(events: [event]),
        actions: [],
        now: { now },
        calendar: Calendar(identifier: .gregorian)
    )

    let snapshot = enricher.enriched(baseCodexSnapshot(), extraNotes: [])

    #expect(snapshot.metrics.first { $0.id == "today-tokens" }?.subvalue == "Cached input 0.0%")
}

@Test func codexSnapshotEnricherDisplaysReportedTotalsWithOneCachedShare() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = Date(timeIntervalSince1970: 1_704_067_200)
    let event = UsageEvent(
        providerID: "codex",
        model: "gpt-5.5 high",
        inputTokens: 1_000,
        outputTokens: 100,
        totalTokens: 1_100,
        cachedInputTokens: 900,
        uncachedInputTokens: 100,
        createdAt: now,
        confidence: .observed
    )
    let enricher = CodexSnapshotEnricher(
        usageLogReader: TestCodexUsageLogReader(events: [event]),
        actions: [],
        now: { now },
        calendar: calendar
    )

    let snapshot = enricher.enriched(baseCodexSnapshot(), extraNotes: [])

    #expect(snapshot.metrics.first { $0.id == "today-tokens" }?.value == "1.1K")
    #expect(snapshot.metrics.first { $0.id == "today-tokens" }?.label == "Today local tokens")
    #expect(snapshot.metrics.first { $0.id == "today-tokens" }?.subvalue == "Cached input 81.8%")
    #expect(snapshot.metrics.first { $0.id == "30d-tokens" }?.value == "1.1K")
    #expect(snapshot.metrics.first { $0.id == "30d-tokens" }?.label == "30d local tokens")
    #expect(snapshot.metrics.first { $0.id == "latest-tokens" }?.value == "1.1K")
    #expect(snapshot.activity?.reduce(0) { $0 + Int($1.value) } == 1_100)
    #expect(snapshot.metrics.first { $0.id == "today-tokens" }?.detail.contains("including cached input") == true)
    #expect(snapshot.notes.contains { $0.contains("reported total_tokens") })
}

@Test func codexSnapshotEnricherUsesAllEventsForCachedShareRegardlessOfModelPricing() {
    let now = Date(timeIntervalSince1970: 1_704_067_200)
    let events = [
        UsageEvent(
            providerID: "codex",
            model: "gpt-5.4",
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            totalTokens: 2_000_000,
            createdAt: now,
            confidence: .observed
        ),
        UsageEvent(
            providerID: "codex",
            model: "unknown-preview",
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            totalTokens: 2_000_000,
            createdAt: now,
            confidence: .observed
        )
    ]
    let enricher = CodexSnapshotEnricher(
        usageLogReader: TestCodexUsageLogReader(events: events),
        actions: [],
        now: { now },
        calendar: Calendar(identifier: .gregorian)
    )

    let snapshot = enricher.enriched(baseCodexSnapshot(), extraNotes: [])

    #expect(snapshot.metrics.first { $0.id == "today-tokens" }?.value == "4.0M")
    #expect(snapshot.metrics.first { $0.id == "today-tokens" }?.subvalue == "Cached input 0.0%")
    #expect(snapshot.metrics.first { $0.id == "30d-tokens" }?.subvalue == "Cached input 0.0%")
}

@Test func codexSnapshotEnricherShowsCachedShareForUnknownModels() {
    let now = Date(timeIntervalSince1970: 1_704_067_200)
    let event = UsageEvent(
        providerID: "codex",
        model: "codex-auto-review low",
        inputTokens: 1_000,
        outputTokens: 100,
        totalTokens: 1_100,
        cachedInputTokens: 500,
        uncachedInputTokens: 500,
        createdAt: now,
        confidence: .observed
    )
    let enricher = CodexSnapshotEnricher(
        usageLogReader: TestCodexUsageLogReader(events: [event]),
        actions: [],
        now: { now },
        calendar: Calendar(identifier: .gregorian)
    )

    let snapshot = enricher.enriched(baseCodexSnapshot(), extraNotes: [])

    #expect(snapshot.metrics.first { $0.id == "today-tokens" }?.subvalue == "Cached input 45.5%")
    #expect(snapshot.metrics.first { $0.id == "30d-tokens" }?.subvalue == "Cached input 45.5%")
}

@Test func codexSnapshotEnricherDoesNotDependOnPriceCoverage() {
    let now = Date(timeIntervalSince1970: 1_704_067_200)
    let events = [
        UsageEvent(
            providerID: "codex",
            model: "gpt-5.4",
            inputTokens: 1_003_000,
            outputTokens: 0,
            totalTokens: 1_003_000,
            cachedInputTokens: 0,
            uncachedInputTokens: 1_003_000,
            createdAt: now,
            confidence: .observed
        ),
        UsageEvent(
            providerID: "codex",
            model: "codex-auto-review low",
            inputTokens: 1_003_000,
            outputTokens: 0,
            totalTokens: 1_003_000,
            cachedInputTokens: 0,
            uncachedInputTokens: 1_003_000,
            createdAt: now,
            confidence: .observed
        )
    ]
    let enricher = CodexSnapshotEnricher(
        usageLogReader: TestCodexUsageLogReader(events: events),
        actions: [],
        now: { now },
        calendar: Calendar(identifier: .gregorian)
    )

    let snapshot = enricher.enriched(baseCodexSnapshot(), extraNotes: [])

    #expect(snapshot.metrics.first { $0.id == "today-tokens" }?.value == "2.0M")
    #expect(snapshot.metrics.first { $0.id == "today-tokens" }?.subvalue == "Cached input 0.0%")
}

@Test func codexSnapshotEnricherCountsCachedOnlyUsageInReportedTotal() {
    let now = Date(timeIntervalSince1970: 1_704_067_200)
    let event = UsageEvent(
        providerID: "codex",
        model: "gpt-5.4",
        inputTokens: 1_000_000,
        outputTokens: 0,
        totalTokens: 1_000_000,
        cachedInputTokens: 1_000_000,
        uncachedInputTokens: 0,
        createdAt: now,
        confidence: .observed
    )
    let enricher = CodexSnapshotEnricher(
        usageLogReader: TestCodexUsageLogReader(events: [event]),
        actions: [],
        now: { now },
        calendar: Calendar(identifier: .gregorian)
    )

    let snapshot = enricher.enriched(baseCodexSnapshot(), extraNotes: [])

    #expect(snapshot.metrics.first { $0.id == "today-tokens" }?.value == "1.0M")
    #expect(snapshot.metrics.first { $0.id == "today-tokens" }?.confidence == .observed)
    #expect(snapshot.metrics.first { $0.id == "today-tokens" }?.subvalue == "Cached input 100.0%")
    #expect(snapshot.metrics.first { $0.id == "top-model" }?.value == "gpt-5.4")
}

@Test func codexSnapshotEnricherExcludesFutureDatedEvents() {
    let now = Date(timeIntervalSince1970: 1_704_067_200)
    let events = [
        UsageEvent(
            providerID: "codex",
            model: "gpt-5.5",
            inputTokens: 900,
            outputTokens: 100,
            totalTokens: 1_000,
            cachedInputTokens: 500,
            createdAt: now,
            confidence: .observed
        ),
        UsageEvent(
            providerID: "codex",
            model: "gpt-5.5",
            inputTokens: 9_000,
            outputTokens: 1_000,
            totalTokens: 10_000,
            cachedInputTokens: 5_000,
            createdAt: now.addingTimeInterval(60),
            confidence: .observed
        )
    ]
    let enricher = CodexSnapshotEnricher(
        usageLogReader: TestCodexUsageLogReader(events: events),
        actions: [],
        now: { now },
        calendar: Calendar(identifier: .gregorian)
    )

    let snapshot = enricher.enriched(baseCodexSnapshot(), extraNotes: [])

    #expect(snapshot.metrics.first { $0.id == "today-tokens" }?.value == "1.0K")
    #expect(snapshot.metrics.first { $0.id == "today-tokens" }?.subvalue == "Cached input 50.0%")
    #expect(snapshot.activity?.reduce(0) { $0 + Int($1.value) } == 1_000)
}

@Test func codexSnapshotEnricherPreservesOfficialQuotaBars() {
    let officialBar = UsageBar(
        id: "codex-session",
        label: "Session",
        remainingFraction: 0.75,
        usedText: "75% left",
        resetText: "Resets in 1h",
        confidence: .official
    )
    let enricher = CodexSnapshotEnricher(
        usageLogReader: TestCodexUsageLogReader(events: []),
        actions: []
    )

    let snapshot = enricher.enriched(baseCodexSnapshot(bars: [officialBar]), extraNotes: [])

    #expect(snapshot.bars == [officialBar])
}

@Test func codexSnapshotEnricherDeduplicatesNotesWhileKeepingOrder() {
    let enricher = CodexSnapshotEnricher(
        usageLogReader: TestCodexUsageLogReader(events: []),
        actions: []
    )
    let snapshot = ProviderSnapshot(
        id: "codex",
        name: "Codex",
        kind: .subscription,
        health: .ready,
        headline: "Synced",
        metrics: [],
        bars: [],
        notes: ["Latest official Codex sync failed", "OAuth API sync failed: unavailable"],
        actions: []
    )

    let enriched = enricher.enriched(
        snapshot,
        extraNotes: ["OAuth API sync failed: unavailable", "CLI RPC sync failed: unavailable"]
    )

    #expect(enriched.notes == [
        "Latest official Codex sync failed",
        "OAuth API sync failed: unavailable",
        "CLI RPC sync failed: unavailable",
        "Local token cards and activity use reported total_tokens, including cached input; replay and duplicate telemetry rows are filtered."
    ])
}

private struct TestCodexUsageLogReader: CodexUsageLogReading {
    let events: [UsageEvent]

    func loadEvents() -> [UsageEvent] {
        events
    }
}

private func baseCodexSnapshot(bars: [UsageBar] = []) -> ProviderSnapshot {
    ProviderSnapshot(
        id: "codex",
        name: "Codex",
        kind: .subscription,
        health: .ready,
        headline: "Synced",
        metrics: [
            UsageMetric(
                id: "source",
                label: "Source",
                value: "Web",
                confidence: .official
            ),
            UsageMetric(
                id: "today-tokens",
                label: "Today tokens",
                value: "stale",
                confidence: .observed
            )
        ],
        bars: bars,
        notes: [],
        actions: []
    )
}
