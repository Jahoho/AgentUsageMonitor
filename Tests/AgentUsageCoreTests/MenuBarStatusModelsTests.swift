import AgentUsageCore
import Foundation
import Testing

@Test func menuBarStatusPrefersLowQuotaProvider() {
    let codex = provider(
        id: "codex",
        name: "Codex",
        health: .ready,
        remainingFraction: 0.12,
        activityValue: 0
    )
    let deepSeek = provider(
        id: "deepseek",
        name: "DeepSeek",
        health: .ready,
        remainingFraction: 0.8,
        activityValue: 900
    )

    let status = MenuBarStatusFactory.snapshot(from: [codex, deepSeek], now: testDate(hour: 9))

    #expect(status.providerID == "codex")
    #expect(status.level == .lowQuota)
    #expect(status.remainingFraction == 0.12)
}

@Test func menuBarStatusUsesMostActiveProviderWhenQuotaIsHealthy() {
    let codex = provider(
        id: "codex",
        name: "Codex",
        health: .ready,
        remainingFraction: 0.67,
        activityValue: 200
    )
    let deepSeek = provider(
        id: "deepseek",
        name: "DeepSeek",
        health: .ready,
        remainingFraction: nil,
        activityValue: 1_400
    )

    let status = MenuBarStatusFactory.snapshot(from: [codex, deepSeek], now: testDate(hour: 9))

    #expect(status.providerID == "deepseek")
    #expect(status.level == .active)
    #expect(status.detail == "Active today")
}

@Test func menuBarStatusUsesCurrentCodexActivityBeforeProviderError() {
    let codex = provider(
        id: "codex",
        name: "Codex",
        health: .ready,
        remainingFraction: nil,
        activityValue: 300
    )
    let deepSeek = provider(
        id: "deepseek",
        name: "DeepSeek",
        health: .error,
        remainingFraction: nil,
        activityValue: 0
    )

    let status = MenuBarStatusFactory.snapshot(from: [deepSeek, codex], now: testDate(hour: 12))

    #expect(status.providerID == "codex")
    #expect(status.level == .active)
    #expect(status.detail == "Active now")
}

@Test func menuBarStatusShowsCodexErrorBeforeCodexObservedActivity() {
    let codex = provider(
        id: "codex",
        name: "Codex",
        health: .error,
        remainingFraction: nil,
        activityValue: 300
    )

    let status = MenuBarStatusFactory.snapshot(from: [codex], now: testDate(hour: 12))

    #expect(status.providerID == "codex")
    #expect(status.level == .error)
    #expect(status.detail == "Error")
}

@Test func menuBarStatusUsesCodexSessionQuotaWhenCodexIsActive() {
    let codex = provider(
        id: "codex",
        name: "Codex",
        health: .ready,
        bars: [
            usageBar(id: "codex-session", label: "Session", remainingFraction: 0.82),
            usageBar(id: "codex-weekly", label: "Weekly", remainingFraction: 0.31)
        ],
        activityValue: 500
    )

    let status = MenuBarStatusFactory.snapshot(from: [codex], now: testDate(hour: 12))

    #expect(status.providerID == "codex")
    #expect(status.level == .active)
    #expect(status.remainingFraction == 0.82)
}

@Test func menuBarStatusUsesCodexSessionQuotaForStaleCodexActivity() {
    let codex = provider(
        id: "codex",
        name: "Codex",
        health: .ready,
        bars: [
            usageBar(id: "codex-session", label: "Session", remainingFraction: 0.74),
            usageBar(id: "codex-weekly", label: "Weekly", remainingFraction: 0.22)
        ],
        activity: [
            UsageActivityBucket(
                id: "hour-8",
                label: "08:00",
                value: 500,
                valueText: "500",
                confidence: .observed
            )
        ]
    )

    let status = MenuBarStatusFactory.snapshot(from: [codex], now: testDate(hour: 12))

    #expect(status.providerID == "codex")
    #expect(status.level == .active)
    #expect(status.detail == "Active today")
    #expect(status.remainingFraction == 0.74)
}

@Test func menuBarStatusDoesNotTreatCodexWeeklyAsMenuBarLowQuotaWhenSessionIsHealthy() {
    let codex = provider(
        id: "codex",
        name: "Codex",
        health: .ready,
        bars: [
            usageBar(id: "codex-session", label: "Session", remainingFraction: 0.82),
            usageBar(id: "codex-weekly", label: "Weekly", remainingFraction: 0.12)
        ],
        activityValue: 0
    )

    let status = MenuBarStatusFactory.snapshot(from: [codex], now: testDate(hour: 12))

    #expect(status.providerID == "codex")
    #expect(status.level == .ready)
    #expect(status.remainingFraction == 0.82)
}

@Test func menuBarStatusFallsBackToSetupWhenNoProviderIsReady() {
    let claude = provider(
        id: "claude",
        name: "Claude",
        health: .needsSetup,
        remainingFraction: nil,
        activityValue: 0
    )

    let status = MenuBarStatusFactory.snapshot(from: [claude])

    #expect(status.providerID == "claude")
    #expect(status.level == .needsSetup)
    #expect(status.remainingFraction == nil)
}

private func testDate(hour: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 3, hour: hour)) ?? Date()
}

private func provider(
    id: String,
    name: String,
    health: ProviderHealth,
    remainingFraction: Double?,
    activityValue: Double
) -> ProviderSnapshot {
    provider(
        id: id,
        name: name,
        health: health,
        bars: [
            usageBar(
                id: "\(id)-quota",
                label: "Quota",
                remainingFraction: remainingFraction
            )
        ],
        activityValue: activityValue
    )
}

private func provider(
    id: String,
    name: String,
    health: ProviderHealth,
    bars: [UsageBar],
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

    return provider(
        id: id,
        name: name,
        health: health,
        bars: bars,
        activity: activity
    )
}

private func provider(
    id: String,
    name: String,
    health: ProviderHealth,
    bars: [UsageBar],
    activity: [UsageActivityBucket]?
) -> ProviderSnapshot {

    return ProviderSnapshot(
        id: id,
        name: name,
        kind: .subscription,
        health: health,
        headline: health.rawValue,
        metrics: [],
        bars: bars,
        activity: activity,
        notes: [],
        actions: []
    )
}

private func usageBar(id: String, label: String, remainingFraction: Double?) -> UsageBar {
    UsageBar(
        id: id,
        label: label,
        remainingFraction: remainingFraction,
        usedText: remainingFraction.map { "\(Int(($0 * 100).rounded()))% left" } ?? "Unavailable",
        resetText: "Unknown",
        confidence: remainingFraction == nil ? .unavailable : .official
    )
}
