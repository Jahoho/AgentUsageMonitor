import Foundation

public enum UsageAggregator {
    public static func overview(from snapshots: [ProviderSnapshot], updatedAt: Date = Date()) -> ProviderSnapshot {
        let readyCount = snapshots.filter { $0.health == .ready }.count
        let setupCount = snapshots.filter { $0.health == .needsSetup }.count
        let unavailableCount = snapshots.filter { $0.health == .unavailable }.count
        let activity = combinedActivity(from: snapshots)
        let todayTokens = Int(activity.reduce(0) { $0 + $1.value }.rounded())
        let mostActiveProvider = mostActiveProvider(from: snapshots)

        let metrics = [
            UsageMetric(
                id: "today-tokens",
                label: "Today",
                value: UsageValueFormatter.tokens(todayTokens),
                detail: "Observed tokens across connected providers today",
                confidence: todayTokens > 0 ? .observed : .unavailable
            ),
            UsageMetric(
                id: "active-provider",
                label: "Active",
                value: mostActiveProvider?.name ?? "Idle",
                detail: mostActiveProvider.map { "Most observed activity today: \($0.tokens) tokens" }
                    ?? "No observed activity yet today",
                confidence: mostActiveProvider == nil ? .unavailable : .observed
            ),
            UsageMetric(
                id: "ready-providers",
                label: "Ready",
                value: "\(readyCount)",
                detail: "Providers with usable data",
                confidence: readyCount > 0 ? .observed : .unavailable
            ),
            UsageMetric(
                id: "needs-setup",
                label: "Needs setup",
                value: "\(setupCount)",
                detail: "Providers waiting for credentials or login",
                confidence: .observed
            ),
            UsageMetric(
                id: "unavailable",
                label: "Unavailable",
                value: "\(unavailableCount)",
                detail: "Providers without a reliable source yet",
                confidence: .observed
            )
        ]

        return ProviderSnapshot(
            id: "overview",
            name: "Overview",
            kind: .local,
            updatedAt: updatedAt,
            health: readyCount > 0 ? .ready : .needsSetup,
            headline: headline(todayTokens: todayTokens, readyCount: readyCount),
            metrics: metrics,
            bars: [],
            activity: activity,
            notes: [
                "Subscription providers and API providers are tracked separately.",
                "Confidence labels prevent estimated values from looking official."
            ],
            actions: []
        )
    }

    private static func headline(todayTokens: Int, readyCount: Int) -> String {
        if todayTokens > 0 {
            return "\(UsageValueFormatter.tokens(todayTokens)) tokens today"
        }

        if readyCount > 0 {
            return "Monitoring \(readyCount) provider(s)"
        }

        return "Connect a provider to start monitoring"
    }

    private static func combinedActivity(from snapshots: [ProviderSnapshot]) -> [UsageActivityBucket] {
        let totalsByHour = snapshots
            .flatMap { $0.activity ?? [] }
            .reduce(into: [String: Double]()) { totals, bucket in
                totals[bucket.id, default: 0] += bucket.value
            }

        return (0..<24).map { hour in
            let id = "hour-\(hour)"
            let value = totalsByHour[id] ?? 0
            let tokens = Int(value.rounded())

            return UsageActivityBucket(
                id: id,
                label: String(format: "%02d:00", hour),
                value: value,
                valueText: UsageValueFormatter.tokens(tokens),
                confidence: tokens > 0 ? .observed : .unavailable
            )
        }
    }

    private static func mostActiveProvider(from snapshots: [ProviderSnapshot]) -> (name: String, tokens: Int)? {
        snapshots
            .compactMap { snapshot -> (name: String, tokens: Int)? in
                let tokens = Int((snapshot.activity ?? []).reduce(0) { $0 + $1.value }.rounded())
                guard tokens > 0 else {
                    return nil
                }

                return (snapshot.name, tokens)
            }
            .max { $0.tokens < $1.tokens }
    }
}
