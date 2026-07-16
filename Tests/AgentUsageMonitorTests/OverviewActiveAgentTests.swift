import AgentUsageCore
import Foundation
import Testing
@testable import AgentUsageMonitor

@Test func overviewActiveAgentDoesNotUseErroredCodexActivityAsActiveProvider() throws {
    let codex = overviewProvider(
        id: "codex",
        name: "Codex",
        health: .error,
        activityValue: 500
    )
    let claude = overviewProvider(
        id: "claude",
        name: "Claude",
        health: .needsSetup,
        activityValue: 0
    )

    let agent = try #require(OverviewActiveAgent.resolve(
        from: [codex, claude],
        now: overviewTestDate(hour: 12)
    ))

    #expect(agent.snapshot.id == "codex")
    #expect(agent.modeText == "Error")
    #expect(agent.currentHourTokens == 500)
}

private func overviewTestDate(hour: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 3, hour: hour)) ?? Date()
}

private func overviewProvider(
    id: String,
    name: String,
    health: ProviderHealth,
    activityValue: Double
) -> ProviderSnapshot {
    let activity: [UsageActivityBucket]? = activityValue > 0
        ? [
            UsageActivityBucket(
                id: "hour-12",
                label: "12:00",
                value: activityValue,
                valueText: "\(Int(activityValue))",
                confidence: .observed
            )
        ]
        : nil

    return ProviderSnapshot(
        id: id,
        name: name,
        kind: .subscription,
        health: health,
        headline: health.rawValue,
        metrics: [],
        bars: [],
        activity: activity,
        notes: [],
        actions: []
    )
}
