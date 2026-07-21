import AgentUsageCore
import Foundation
import Testing

@Test func legacyLongPrimaryHistoryNormalizesToWeeklyWithoutChangingSessionHistory() {
    let start = weeklyReviewDate()
    let weeklyReset = start.addingTimeInterval(7 * 24 * 60 * 60)
    let sessionReset = start.addingTimeInterval(5 * 60 * 60)
    let observations = [
        weeklyReviewObservation(remaining: 1, capturedAt: start, resetAt: weeklyReset),
        weeklyReviewObservation(
            remaining: 0.3,
            capturedAt: weeklyReset.addingTimeInterval(-4 * 60 * 60),
            resetAt: weeklyReset
        ),
        weeklyReviewObservation(
            remaining: 0.8,
            capturedAt: start,
            resetAt: sessionReset,
            accountScopeID: "short-window"
        )
    ]

    let normalized = CodexQuotaObservationNormalizer.normalize(observations)

    #expect(normalized[0].quotaID == "codex-weekly")
    #expect(normalized[1].quotaID == "codex-weekly")
    #expect(normalized[2].quotaID == "codex-session")
}

@Test func weeklyReviewSummarizesCurrentCycleAndReportsCoverageHonestly() throws {
    let start = weeklyReviewDate()
    let resetAt = start.addingTimeInterval(7 * 24 * 60 * 60)
    let points = [
        weeklyReviewObservation(remaining: 1, capturedAt: start, resetAt: resetAt),
        weeklyReviewObservation(
            remaining: 0.8,
            capturedAt: start.addingTimeInterval(24 * 60 * 60),
            resetAt: resetAt
        ),
        weeklyReviewObservation(
            remaining: 0.6,
            capturedAt: start.addingTimeInterval(48 * 60 * 60),
            resetAt: resetAt
        )
    ]

    let latest = points[points.count - 1]
    let review = try #require(
        WeeklySubscriptionReviewAnalyzer.analyze(
            current: [latest],
            history: points,
            now: latest.capturedAt
        )
    )
    let cycle = try #require(review.currentCycle)

    #expect(review.confidence == .observed)
    #expect(cycle.usageScope == .cycleToDate)
    #expect(abs(cycle.observedUsedFraction - 0.4) < 0.000_001)
    #expect(abs((cycle.cycleCoverageFraction ?? 0) - (2.0 / 7.0)) < 0.000_001)
    #expect(cycle.sampleCount == 3)
    #expect(cycle.sampleCoverageFraction < 0.01)
    #expect(review.comparisonAvailabilityReason == .noPreviousCycle)
}

@Test func weeklyReviewComparesWithPreviousCycleAtTheSameProgress() throws {
    let previousStart = weeklyReviewDate()
    let currentStart = previousStart.addingTimeInterval(7 * 24 * 60 * 60)
    let progress: TimeInterval = 48 * 60 * 60
    let points = [
        weeklyReviewObservation(
            remaining: 1,
            capturedAt: previousStart,
            resetAt: currentStart
        ),
        weeklyReviewObservation(
            remaining: 0.8,
            capturedAt: previousStart.addingTimeInterval(progress),
            resetAt: currentStart
        ),
        weeklyReviewObservation(
            remaining: 1,
            capturedAt: currentStart,
            resetAt: currentStart.addingTimeInterval(7 * 24 * 60 * 60)
        ),
        weeklyReviewObservation(
            remaining: 0.7,
            capturedAt: currentStart.addingTimeInterval(progress),
            resetAt: currentStart.addingTimeInterval(7 * 24 * 60 * 60)
        )
    ]

    let latest = points[points.count - 1]
    let review = try #require(
        WeeklySubscriptionReviewAnalyzer.analyze(
            current: [latest],
            history: points,
            now: latest.capturedAt
        )
    )
    let comparison = try #require(review.comparison)

    #expect(abs(comparison.remainingDifferenceFraction + 0.1) < 0.000_001)
    #expect(comparison.previousRemainingFraction == 0.8)
    #expect(comparison.matchedProgressDifference == 0)
    #expect(review.comparisonAvailabilityReason == nil)
}

@Test func weeklyReviewTreatsResetTimeAdjustmentsAsOneCycleUntilCapacityRefills() throws {
    let start = weeklyReviewDate()
    let firstReset = start.addingTimeInterval(6 * 24 * 60 * 60)
    let laterReset = start.addingTimeInterval(7 * 24 * 60 * 60)
    let points = [
        weeklyReviewObservation(remaining: 1, capturedAt: start, resetAt: firstReset),
        weeklyReviewObservation(
            remaining: 1,
            capturedAt: start.addingTimeInterval(10 * 60),
            resetAt: laterReset
        ),
        weeklyReviewObservation(
            remaining: 0.75,
            capturedAt: start.addingTimeInterval(2 * 60 * 60),
            resetAt: laterReset
        )
    ]

    let latest = points[points.count - 1]
    let review = try #require(
        WeeklySubscriptionReviewAnalyzer.analyze(
            current: [latest],
            history: points,
            now: latest.capturedAt
        )
    )
    let cycle = try #require(review.currentCycle)

    #expect(cycle.sampleCount == 3)
    #expect(abs(cycle.observedUsedFraction - 0.25) < 0.000_001)
    #expect(review.comparisonAvailabilityReason == .noPreviousCycle)
}

@Test func weeklyReviewLabelsMidCycleHistoryAsObservedSpan() throws {
    let start = weeklyReviewDate()
    let resetAt = start.addingTimeInterval(3 * 24 * 60 * 60)
    let points = [
        weeklyReviewObservation(remaining: 0.8, capturedAt: start, resetAt: resetAt),
        weeklyReviewObservation(
            remaining: 0.6,
            capturedAt: start.addingTimeInterval(2 * 60 * 60),
            resetAt: resetAt
        )
    ]

    let latest = points[points.count - 1]
    let review = try #require(
        WeeklySubscriptionReviewAnalyzer.analyze(
            current: [latest],
            history: points,
            now: latest.capturedAt
        )
    )
    let cycle = try #require(review.currentCycle)

    #expect(cycle.usageScope == .observedSpan)
    #expect(cycle.cycleCoverageFraction == nil)
    #expect(abs(cycle.observedUsedFraction - 0.2) < 0.000_001)
}

private func weeklyReviewDate() -> Date {
    Date(timeIntervalSince1970: 1_800_000_000)
}

private func weeklyReviewObservation(
    remaining: Double,
    capturedAt: Date,
    resetAt: Date,
    accountScopeID: String = "account",
    quotaID: String = "codex-session"
) -> QuotaObservation {
    QuotaObservation(
        providerID: "codex",
        accountScopeID: accountScopeID,
        quotaID: quotaID,
        remainingFraction: remaining,
        capturedAt: capturedAt,
        resetAt: resetAt
    )
}
