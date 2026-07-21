import AgentUsageCore
import Foundation
import Testing
@testable import AgentUsageMonitor

@Test func weeklyRecapPresentationShowsOutcomeRhythmBaselineAndPlanFit() {
    let review = weeklyPresentationReview(
        rhythm: WeeklySubscriptionRhythmSummary(
            pattern: .concentrated,
            activeDayCount: 2,
            peakWeekday: 3,
            topTwoDayUseFraction: 0.82,
            attributedUseFraction: 0.9
        ),
        baselineComparison: WeeklySubscriptionBaselineComparison(
            usedDifferenceFraction: 0.09,
            medianUsedFraction: 0.67,
            comparisonCycleCount: 4
        ),
        planFit: WeeklySubscriptionPlanFitSummary(
            pattern: .ampleHeadroom,
            evaluatedCycleCount: 4,
            ampleHeadroomCycleCount: 3,
            nearLimitCycleCount: 0
        ),
        eligibleCycleCount: 5
    )
    let presentation = WeeklySubscriptionReviewPresentation(review: review)

    #expect(presentation.periodText != nil)
    #expect(presentation.primaryText == "A concentrated week")
    #expect(presentation.summaryText == "Observed use spanned 2 days, peaking Tue; 24% remained near reset.")
    #expect(presentation.rhythmText == "Concentrated across 2 days · largest drop Tue")
    #expect(presentation.capacityText == "24% remained near reset · low-headroom zone not reached")
    #expect(presentation.baselineText == "9 pp more quota used than your recent 4-cycle median")
    #expect(presentation.planFitText == "Ample headroom in 3 of 4 cycles")
    #expect(presentation.dataQualityText == "62% of expected Official samples · final sample <1h before reset")
}

@Test func weeklyRecapPresentationExplainsWhenPersonalHistoryIsStillGrowing() {
    let review = weeklyPresentationReview(
        rhythm: nil,
        baselineComparison: nil,
        planFit: nil,
        eligibleCycleCount: 1
    )
    let presentation = WeeklySubscriptionReviewPresentation(review: review)

    #expect(presentation.primaryText == "Weekly recap ready")
    #expect(presentation.summaryText == "24% remained near reset; rhythm needs more continuous samples.")
    #expect(presentation.baselineText == "Needs 3 earlier complete cycles · 0 available")
    #expect(presentation.planFitText == "Needs 3 complete cycles · 1 available")
}

@Test func weeklyRecapPresentationWaitsForTheFirstCompletedReset() {
    let review = WeeklySubscriptionReview.unavailable(
        providerID: "codex",
        reason: .noCompletedCycle,
        generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
        currentResetAt: Date(timeIntervalSince1970: 1_800_604_800)
    )
    let presentation = WeeklySubscriptionReviewPresentation(review: review)

    #expect(presentation.primaryText == "First weekly recap is still being prepared.")
    #expect(presentation.summaryText == "It will appear after a fully observed weekly reset.")
}

@Test func weeklyRecapPresentationFailsClosedWithoutCurrentOfficialQuota() {
    let review = WeeklySubscriptionReview.unavailable(
        providerID: "codex",
        reason: .currentQuotaUnavailable,
        generatedAt: Date(timeIntervalSince1970: 1_800_000_000)
    )
    let presentation = WeeklySubscriptionReviewPresentation(review: review)

    #expect(presentation.primaryText == "Current Official weekly quota is unavailable.")
    #expect(presentation.summaryText == "Historical recap is not shown without current Official quota.")
}

private func weeklyPresentationReview(
    rhythm: WeeklySubscriptionRhythmSummary?,
    baselineComparison: WeeklySubscriptionBaselineComparison?,
    planFit: WeeklySubscriptionPlanFitSummary?,
    eligibleCycleCount: Int
) -> WeeklySubscriptionReview {
    let start = Date(timeIntervalSince1970: 1_800_057_600)
    let resetAt = start.addingTimeInterval(7 * 24 * 60 * 60)
    return WeeklySubscriptionReview(
        providerID: "codex",
        currentResetAt: resetAt.addingTimeInterval(7 * 24 * 60 * 60),
        completedCycle: WeeklySubscriptionCompletedCycleSummary(
            quotaID: "codex-weekly",
            startedAt: start,
            resetAt: resetAt,
            endingRemainingFraction: 0.24,
            lowestRemainingFraction: 0.24,
            observedUsedFraction: 0.76,
            sampleCount: 1_250,
            sampleCoverageFraction: 0.62,
            endObservationLead: 30 * 60,
            rhythm: rhythm
        ),
        baselineComparison: baselineComparison,
        planFit: planFit,
        eligibleCompletedCycleCount: eligibleCycleCount,
        generatedAt: resetAt.addingTimeInterval(60 * 60)
    )
}
