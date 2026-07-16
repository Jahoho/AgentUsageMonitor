import AgentUsageCore
import Testing

@Test func overviewCountsProviderHealth() {
    let snapshots = [
        ProviderSnapshot.unavailable(
            id: "codex",
            name: "Codex",
            kind: .subscription,
            headline: "No source",
            notes: []
        ),
        ProviderSnapshot(
            id: "deepseek",
            name: "DeepSeek",
            kind: .api,
            health: .ready,
            headline: "Ready",
            metrics: [],
            bars: [],
            notes: [],
            actions: []
        )
    ]

    let overview = UsageAggregator.overview(from: snapshots)

    #expect(overview.id == "overview")
    #expect(overview.health == .ready)
    #expect(overview.metrics.first { $0.id == "today-tokens" }?.value == "0")
    #expect(overview.metrics.first { $0.id == "ready-providers" }?.value == "1")
    #expect(overview.metrics.first { $0.id == "unavailable" }?.value == "1")
}

@Test func overviewCombinesProviderActivityByHour() {
    let snapshots = [
        activitySnapshot(
            id: "codex",
            name: "Codex",
            buckets: [
                bucket(hour: 9, tokens: 1_200),
                bucket(hour: 10, tokens: 800)
            ]
        ),
        activitySnapshot(
            id: "deepseek",
            name: "DeepSeek",
            buckets: [
                bucket(hour: 9, tokens: 300),
                bucket(hour: 12, tokens: 2_000)
            ]
        )
    ]

    let overview = UsageAggregator.overview(from: snapshots)

    #expect(overview.headline == "4.3K tokens today")
    #expect(overview.metrics.first { $0.id == "today-tokens" }?.value == "4.3K")
    #expect(overview.metrics.first { $0.id == "active-provider" }?.value == "DeepSeek")
    #expect(overview.activity?.count == 24)
    #expect(overview.activity?.first { $0.id == "hour-9" }?.value == 1_500)
    #expect(overview.activity?.first { $0.id == "hour-10" }?.value == 800)
    #expect(overview.activity?.first { $0.id == "hour-12" }?.value == 2_000)
}

private func activitySnapshot(
    id: String,
    name: String,
    buckets: [UsageActivityBucket]
) -> ProviderSnapshot {
    ProviderSnapshot(
        id: id,
        name: name,
        kind: .subscription,
        health: .ready,
        headline: "Ready",
        metrics: [],
        bars: [],
        activity: buckets,
        notes: [],
        actions: []
    )
}

private func bucket(hour: Int, tokens: Int) -> UsageActivityBucket {
    UsageActivityBucket(
        id: "hour-\(hour)",
        label: String(format: "%02d:00", hour),
        value: Double(tokens),
        valueText: "\(tokens)",
        confidence: .observed
    )
}
