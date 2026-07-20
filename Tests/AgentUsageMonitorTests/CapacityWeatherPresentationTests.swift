import AgentUsageCore
import Foundation
import Testing
@testable import AgentUsageMonitor

@Test func capacityWeatherPresentationLearnsWhileReadyHistoryIsMissing() {
    let snapshot = weatherSnapshot(health: .ready)

    let insight = CapacityWeatherPresentation.resolvedInsight(
        snapshot: snapshot,
        insight: nil
    )
    let presentation = CapacityWeatherPresentation(snapshot: snapshot, insight: insight)

    #expect(insight.weather == .learning)
    #expect(insight.confidence == .unavailable)
    #expect(presentation.title == "Learning your pace")
    #expect(presentation.summary.contains("More Official samples"))
}

@Test func capacityWeatherPresentationShowsFogWithoutHistoricalFallback() {
    let snapshot = weatherSnapshot(health: .error)

    let insight = CapacityWeatherPresentation.resolvedInsight(
        snapshot: snapshot,
        insight: nil
    )
    let presentation = CapacityWeatherPresentation(snapshot: snapshot, insight: insight)

    #expect(insight.weather == .fog)
    #expect(insight.confidence == .unavailable)
    #expect(presentation.summary.contains("Previous history is not used"))
}

@Test func capacityWeatherPresentationLabelsTightHeadroomAsEstimated() {
    let snapshot = weatherSnapshot(health: .ready)
    let now = snapshot.updatedAt
    let resetAt = now.addingTimeInterval(2 * 3_600)
    let window = HeadroomWindowInsight(
        quotaID: "codex-weekly",
        weather: .windy,
        currentRemainingFraction: 0.25,
        projectedRemainingAtReset: 0.1,
        projectedExhaustionAt: nil,
        resetAt: resetAt,
        consumptionPerHour: 0.075,
        sampleCount: 12,
        coverageDuration: 6 * 3_600,
        sampleCoverageFraction: 0.8
    )
    let insight = CapacityInsight(
        providerID: "codex",
        weather: .windy,
        constrainingQuotaID: window.quotaID,
        windows: [window],
        generatedAt: now
    )
    let presentation = CapacityWeatherPresentation(snapshot: snapshot, insight: insight)

    #expect(insight.confidence == .estimated)
    #expect(presentation.title == "Headroom narrowing")
    #expect(presentation.summary.contains("Weekly should reach reset with only 10% left"))
    #expect(presentation.sourceNote.contains("Current Official data remains the source of truth"))
}

private func weatherSnapshot(health: ProviderHealth) -> ProviderSnapshot {
    let now = Date(timeIntervalSince1970: 1_750_000_000)
    return ProviderSnapshot(
        id: "codex",
        name: "Codex",
        kind: .subscription,
        updatedAt: now,
        health: health,
        headline: "Current official quota",
        metrics: [],
        bars: [
            UsageBar(
                id: "codex-weekly",
                label: "Weekly",
                remainingFraction: 0.25,
                usedText: "75% used",
                resetText: "Resets later",
                resetAt: now.addingTimeInterval(2 * 3_600),
                confidence: .official
            )
        ],
        notes: [],
        actions: []
    )
}
