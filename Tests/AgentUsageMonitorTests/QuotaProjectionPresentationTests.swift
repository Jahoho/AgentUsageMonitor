import AgentUsageCore
import Foundation
import Testing
@testable import AgentUsageMonitor

@Test func quotaProjectionPresentationWaitsForHistoryWhenCurrentQuotaIsReady() {
    let snapshot = projectionSnapshot(health: .ready)

    let projection = QuotaProjectionPresentation.resolvedProjection(
        snapshot: snapshot,
        projection: nil
    )
    let presentation = QuotaProjectionPresentation(
        snapshot: snapshot,
        projection: projection
    )

    #expect(projection.confidence == .unavailable)
    #expect(projection.availabilityReason == .insufficientHistory)
    #expect(presentation.primaryText == "Collecting more history before projecting.")
    #expect(presentation.detailText.contains("source of truth"))
}

@Test func quotaProjectionPresentationDoesNotUseHistoryAsCurrentQuotaFallback() {
    let snapshot = projectionSnapshot(health: .error)

    let projection = QuotaProjectionPresentation.resolvedProjection(
        snapshot: snapshot,
        projection: nil
    )
    let presentation = QuotaProjectionPresentation(
        snapshot: snapshot,
        projection: projection
    )

    #expect(projection.confidence == .unavailable)
    #expect(projection.availabilityReason == .currentQuotaUnavailable)
    #expect(presentation.primaryText == "Current Official quota is unavailable.")
    #expect(presentation.detailText.contains("Previous history is not used"))
}

@Test func quotaProjectionPresentationShowsACompactEstimatedRange() throws {
    let snapshot = projectionSnapshot(health: .ready)
    let window = projectionWindow(
        projectedRemaining: 0.1,
        lowerBound: 0.07,
        upperBound: 0.13
    )
    let projection = QuotaProjection(
        providerID: "codex",
        constrainingQuotaID: window.quotaID,
        windows: [window],
        generatedAt: snapshot.updatedAt
    )

    let presentation = QuotaProjectionPresentation(
        snapshot: snapshot,
        projection: projection
    )

    #expect(projection.confidence == .estimated)
    #expect(presentation.primaryText == "Weekly: 7–13% expected to remain at reset.")
    #expect(presentation.detailText == "Based on 6h of recent Official history.")
}

@Test func quotaProjectionPresentationShowsPossibleExhaustionWithoutFalsePrecision() {
    let snapshot = projectionSnapshot(health: .ready)
    let window = projectionWindow(
        projectedRemaining: 0,
        lowerBound: -0.04,
        upperBound: 0.04
    )
    let projection = QuotaProjection(
        providerID: "codex",
        constrainingQuotaID: window.quotaID,
        windows: [window],
        generatedAt: snapshot.updatedAt
    )

    let presentation = QuotaProjectionPresentation(
        snapshot: snapshot,
        projection: projection
    )

    #expect(window.outcome == .mayExhaustBeforeReset)
    #expect(presentation.primaryText == "Weekly may run out before reset.")
}

@Test func quotaProjectionPresentationOmitsExhaustionTimeForAWideRange() {
    let snapshot = projectionSnapshot(health: .ready)
    let window = QuotaWindowProjection(
        quotaID: "codex-weekly",
        currentRemainingFraction: 0.4,
        projectedRemainingAtReset: -0.5,
        projectedRemainingLowerBound: -1,
        projectedRemainingUpperBound: -0.1,
        projectedExhaustionAt: snapshot.updatedAt.addingTimeInterval(24 * 3_600),
        resetAt: snapshot.updatedAt.addingTimeInterval(4 * 24 * 3_600),
        consumptionPerHour: 0.02,
        sampleCount: 100,
        coverageDuration: 30 * 3_600,
        sampleCoverageFraction: 0.5,
        forecastErrorFraction: 0.5
    )
    let projection = QuotaProjection(
        providerID: "codex",
        constrainingQuotaID: window.quotaID,
        windows: [window],
        generatedAt: snapshot.updatedAt
    )

    let presentation = QuotaProjectionPresentation(
        snapshot: snapshot,
        projection: projection
    )

    #expect(presentation.primaryText == "Weekly is expected to run out before reset.")
}

private func projectionWindow(
    projectedRemaining: Double,
    lowerBound: Double,
    upperBound: Double
) -> QuotaWindowProjection {
    let now = Date(timeIntervalSince1970: 1_750_000_000)
    return QuotaWindowProjection(
        quotaID: "codex-weekly",
        currentRemainingFraction: 0.25,
        projectedRemainingAtReset: projectedRemaining,
        projectedRemainingLowerBound: lowerBound,
        projectedRemainingUpperBound: upperBound,
        projectedExhaustionAt: now.addingTimeInterval(60 * 60),
        resetAt: now.addingTimeInterval(2 * 3_600),
        consumptionPerHour: 0.075,
        sampleCount: 12,
        coverageDuration: 6 * 3_600,
        sampleCoverageFraction: 0.8,
        forecastErrorFraction: 0.03
    )
}

private func projectionSnapshot(health: ProviderHealth) -> ProviderSnapshot {
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
