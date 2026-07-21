import AgentUsageCore
import Foundation
import Testing
@testable import AgentUsageMonitor

@Test func weeklyReviewPresentationShowsUsageCoverageAndSamePointComparison() {
    let review = weeklyPresentationReview(
        difference: -0.12,
        comparisonReason: nil
    )
    let presentation = WeeklySubscriptionReviewPresentation(review: review)

    #expect(presentation.primaryText == "40% used so far this cycle.")
    #expect(presentation.compactComparisonText == "12 pp less remaining than last cycle at this point.")
    #expect(presentation.coverageText == "29% of cycle · 2d")
    #expect(presentation.samplingText == "50% of expected samples · 289 saved")
    #expect(presentation.expandedComparisonText == presentation.compactComparisonText)
}

@Test func weeklyReviewPresentationExplainsMissingPreviousCoverage() {
    let review = weeklyPresentationReview(
        difference: nil,
        comparisonReason: .insufficientPreviousCoverage
    )
    let presentation = WeeklySubscriptionReviewPresentation(review: review)

    #expect(presentation.compactComparisonText == "Building a fair same-point comparison with the previous cycle.")
    #expect(presentation.expandedComparisonText == "The previous cycle was not observed from near its start.")
}

@Test func weeklyReviewPresentationFailsClosedWithoutCurrentOfficialQuota() {
    let review = WeeklySubscriptionReview.unavailable(
        providerID: "codex",
        reason: .currentQuotaUnavailable,
        generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
    let presentation = WeeklySubscriptionReviewPresentation(review: review)

    #expect(presentation.primaryText == "Current Official weekly quota is unavailable.")
    #expect(presentation.compactComparisonText == "Previous history is not shown without current Official quota.")
}

private func weeklyPresentationReview(
    difference: Double?,
    comparisonReason: WeeklySubscriptionComparisonAvailabilityReason?
) -> WeeklySubscriptionReview {
    let comparison = difference.map { difference in
        WeeklySubscriptionComparison(
            remainingDifferenceFraction: difference,
            previousRemainingFraction: 0.72,
            matchedProgressDifference: 0
        )
    }
    return WeeklySubscriptionReview(
        providerID: "codex",
        currentCycle: WeeklySubscriptionCycleSummary(
            quotaID: "codex-weekly",
            resetAt: Date(timeIntervalSince1970: 1_800_604_800),
            currentRemainingFraction: 0.6,
            observedUsedFraction: 0.4,
            sampleCount: 289,
            coverageDuration: 2 * 24 * 60 * 60,
            cycleCoverageFraction: 2.0 / 7.0,
            sampleCoverageFraction: 0.5,
            usageScope: .cycleToDate
        ),
        comparison: comparison,
        comparisonAvailabilityReason: comparisonReason,
        generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
}
