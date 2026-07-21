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

@Test func weeklyReviewWaitsForACompletedCycleInsteadOfRepeatingCurrentUsage() throws {
    let start = weeklyReviewDate()
    let resetAt = start.addingTimeInterval(WeeklySubscriptionReviewAnalyzer.nominalWeeklyDuration)
    let first = weeklyReviewObservation(
        remaining: 1,
        capturedAt: start,
        resetAt: resetAt,
        quotaID: "codex-weekly"
    )
    let latest = weeklyReviewObservation(
        remaining: 0.7,
        capturedAt: start.addingTimeInterval(3 * 24 * 60 * 60),
        resetAt: resetAt,
        quotaID: "codex-weekly"
    )

    let review = try #require(
        WeeklySubscriptionReviewAnalyzer.analyze(
            current: [latest],
            history: [first, latest],
            now: latest.capturedAt,
            calendar: weeklyReviewCalendar()
        )
    )

    #expect(review.confidence == .unavailable)
    #expect(review.completedCycle == nil)
    #expect(review.availabilityReason == .noCompletedCycle)
    #expect(review.currentResetAt == resetAt)
}

@Test func weeklyReviewDoesNotTreatAPreResetCapacityAdjustmentAsACompletedCycle() throws {
    let start = weeklyReviewDate()
    let firstReset = start.addingTimeInterval(5 * 24 * 60 * 60)
    let adjustedReset = start.addingTimeInterval(7 * 24 * 60 * 60)
    let latest = weeklyReviewObservation(
        remaining: 0.7,
        capturedAt: start.addingTimeInterval(3 * 24 * 60 * 60),
        resetAt: adjustedReset,
        quotaID: "codex-weekly"
    )
    let history = [
        weeklyReviewObservation(
            remaining: 0.8,
            capturedAt: start,
            resetAt: firstReset,
            quotaID: "codex-weekly"
        ),
        weeklyReviewObservation(
            remaining: 1,
            capturedAt: start.addingTimeInterval(24 * 60 * 60),
            resetAt: adjustedReset,
            quotaID: "codex-weekly"
        ),
        latest
    ]

    let review = try #require(
        WeeklySubscriptionReviewAnalyzer.analyze(
            current: [latest],
            history: history,
            now: latest.capturedAt,
            calendar: weeklyReviewCalendar()
        )
    )

    #expect(review.availabilityReason == .noCompletedCycle)
    #expect(review.completedCycle == nil)
}

@Test func weeklyReviewRecapsCompletedOutcomeAndConcentratedRhythm() throws {
    let calendar = weeklyReviewCalendar()
    let start = weeklyReviewDate()
    let completed = weeklyReviewCycle(
        start: start,
        dailyDrops: [0.30, 0.25, 0, 0, 0, 0, 0]
    )
    let current = currentWeeklyObservation(start: completed[0].resetAt)

    let review = try #require(
        WeeklySubscriptionReviewAnalyzer.analyze(
            current: [current],
            history: completed,
            now: current.capturedAt,
            calendar: calendar
        )
    )
    let cycle = try #require(review.completedCycle)
    let rhythm = try #require(cycle.rhythm)

    #expect(review.confidence == .observed)
    #expect(cycle.endingRemainingFraction < 0.46)
    #expect(cycle.endingRemainingFraction > 0.44)
    #expect(cycle.sampleCoverageFraction >= 0.15)
    #expect(cycle.endObservationLead == 30 * 60)
    #expect(rhythm.pattern == .concentrated)
    #expect(rhythm.activeDayCount == 2)
    #expect(rhythm.peakWeekday == calendar.component(.weekday, from: start))
    #expect(review.baselineComparison == nil)
    #expect(review.planFit == nil)
    #expect(review.eligibleCompletedCycleCount == 1)
}

@Test func weeklyReviewUsesPreviousCyclesForPersonalBaselineAndPlanFit() throws {
    let calendar = weeklyReviewCalendar()
    let firstStart = weeklyReviewDate()
    let weeklyDuration = WeeklySubscriptionReviewAnalyzer.nominalWeeklyDuration
    let totals = [0.20, 0.40, 0.60, 0.70]
    let completedCycles = totals.enumerated().flatMap { index, totalUse in
        weeklyReviewCycle(
            start: firstStart.addingTimeInterval(TimeInterval(index) * weeklyDuration),
            dailyDrops: Array(repeating: totalUse / 7, count: 7)
        )
    }
    let currentStart = firstStart.addingTimeInterval(TimeInterval(totals.count) * weeklyDuration)
    let current = currentWeeklyObservation(start: currentStart)

    let review = try #require(
        WeeklySubscriptionReviewAnalyzer.analyze(
            current: [current],
            history: completedCycles,
            now: current.capturedAt,
            calendar: calendar
        )
    )
    let baseline = try #require(review.baselineComparison)
    let planFit = try #require(review.planFit)

    #expect(abs(baseline.medianUsedFraction - 0.40) < 0.01)
    #expect(abs(baseline.usedDifferenceFraction - 0.30) < 0.01)
    #expect(baseline.comparisonCycleCount == 3)
    #expect(planFit.pattern == .ampleHeadroom)
    #expect(planFit.ampleHeadroomCycleCount == 3)
    #expect(planFit.evaluatedCycleCount == 4)
}

@Test func weeklyReviewReportsRepeatedLowHeadroomWithoutRecommendingAPlanChange() throws {
    let firstStart = weeklyReviewDate()
    let weeklyDuration = WeeklySubscriptionReviewAnalyzer.nominalWeeklyDuration
    let totals = [0.96, 0.97, 0.40]
    let completedCycles = totals.enumerated().flatMap { index, totalUse in
        weeklyReviewCycle(
            start: firstStart.addingTimeInterval(TimeInterval(index) * weeklyDuration),
            dailyDrops: Array(repeating: totalUse / 7, count: 7)
        )
    }
    let currentStart = firstStart.addingTimeInterval(TimeInterval(totals.count) * weeklyDuration)
    let current = currentWeeklyObservation(start: currentStart)

    let review = try #require(
        WeeklySubscriptionReviewAnalyzer.analyze(
            current: [current],
            history: completedCycles,
            now: current.capturedAt,
            calendar: weeklyReviewCalendar()
        )
    )
    let planFit = try #require(review.planFit)

    #expect(planFit.pattern == .frequentPressure)
    #expect(planFit.nearLimitCycleCount == 2)
    #expect(planFit.evaluatedCycleCount == 3)
}

@Test func weeklyReviewRejectsACompletedCycleWithoutTrustworthyCoverage() throws {
    let start = weeklyReviewDate()
    let resetAt = start.addingTimeInterval(WeeklySubscriptionReviewAnalyzer.nominalWeeklyDuration)
    let sparse = [
        weeklyReviewObservation(
            remaining: 1,
            capturedAt: start,
            resetAt: resetAt,
            quotaID: "codex-weekly"
        ),
        weeklyReviewObservation(
            remaining: 0.5,
            capturedAt: resetAt.addingTimeInterval(-30 * 60),
            resetAt: resetAt,
            quotaID: "codex-weekly"
        )
    ]
    let current = currentWeeklyObservation(start: resetAt)

    let review = try #require(
        WeeklySubscriptionReviewAnalyzer.analyze(
            current: [current],
            history: sparse,
            now: current.capturedAt,
            calendar: weeklyReviewCalendar()
        )
    )

    #expect(review.confidence == .unavailable)
    #expect(review.availabilityReason == .insufficientCompletedCycleCoverage)
}

@Test func weeklyReviewDoesNotAssignCrossGapUseToOneDay() throws {
    let start = weeklyReviewDate()
    let gapStart = start.addingTimeInterval(2 * 24 * 60 * 60)
    let gapEnd = gapStart.addingTimeInterval(8 * 60 * 60)
    let completed = weeklyReviewCycle(
        start: start,
        dailyDrops: Array(repeating: 0, count: 7)
    )
        .filter { point in
            point.capturedAt <= gapStart || point.capturedAt >= gapEnd
        }
        .map { point in
            weeklyReviewObservation(
                remaining: point.capturedAt < gapEnd ? 1 : 0.5,
                capturedAt: point.capturedAt,
                resetAt: point.resetAt,
                quotaID: "codex-weekly"
            )
        }
    let current = currentWeeklyObservation(start: completed[0].resetAt)

    let review = try #require(
        WeeklySubscriptionReviewAnalyzer.analyze(
            current: [current],
            history: completed,
            now: current.capturedAt,
            calendar: weeklyReviewCalendar()
        )
    )

    #expect(review.completedCycle?.rhythm == nil)
    #expect(review.completedCycle?.sampleCoverageFraction ?? 0 > 0.15)
}

@Test func weeklyReviewKeepsResetTimeAdjustmentsInsideOneCompletedCycle() throws {
    let start = weeklyReviewDate()
    let finalReset = start.addingTimeInterval(WeeklySubscriptionReviewAnalyzer.nominalWeeklyDuration)
    let earlierReset = finalReset.addingTimeInterval(-12 * 60 * 60)
    let adjusted = weeklyReviewCycle(
        start: start,
        dailyDrops: Array(repeating: 0.06, count: 7)
    ).enumerated().map { index, point in
        weeklyReviewObservation(
            remaining: point.remainingFraction,
            capturedAt: point.capturedAt,
            resetAt: index < 48 ? earlierReset : finalReset,
            quotaID: "codex-weekly"
        )
    }
    let current = currentWeeklyObservation(start: finalReset)

    let review = try #require(
        WeeklySubscriptionReviewAnalyzer.analyze(
            current: [current],
            history: adjusted,
            now: current.capturedAt,
            calendar: weeklyReviewCalendar()
        )
    )

    #expect(review.completedCycle?.sampleCount == adjusted.count)
    #expect(review.availabilityReason == nil)
}

private func weeklyReviewDate() -> Date {
    // A stable UTC midnight keeps daily rhythm tests independent of the host time zone.
    Date(timeIntervalSince1970: 1_800_057_600)
}

private func weeklyReviewCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

private func weeklyReviewCycle(
    start: Date,
    dailyDrops: [Double],
    accountScopeID: String = "account"
) -> [QuotaObservation] {
    precondition(dailyDrops.count == 7)
    let sampleInterval: TimeInterval = 30 * 60
    let dayDuration: TimeInterval = 24 * 60 * 60
    let resetAt = start.addingTimeInterval(WeeklySubscriptionReviewAnalyzer.nominalWeeklyDuration)
    let sampleCount = Int(WeeklySubscriptionReviewAnalyzer.nominalWeeklyDuration / sampleInterval)

    return (0..<sampleCount).map { sample in
        let elapsed = TimeInterval(sample) * sampleInterval
        let dayIndex = min(6, Int(elapsed / dayDuration))
        let elapsedInDay = elapsed - (TimeInterval(dayIndex) * dayDuration)
        let completedUse = dailyDrops.prefix(dayIndex).reduce(0, +)
        let currentDayUse = dailyDrops[dayIndex] * min(1, elapsedInDay / dayDuration)
        let remaining = max(0, 1 - completedUse - currentDayUse)
        return weeklyReviewObservation(
            remaining: remaining,
            capturedAt: start.addingTimeInterval(elapsed),
            resetAt: resetAt,
            accountScopeID: accountScopeID,
            quotaID: "codex-weekly"
        )
    }
}

private func currentWeeklyObservation(
    start: Date,
    accountScopeID: String = "account"
) -> QuotaObservation {
    weeklyReviewObservation(
        remaining: 0.99,
        capturedAt: start.addingTimeInterval(60 * 60),
        resetAt: start.addingTimeInterval(WeeklySubscriptionReviewAnalyzer.nominalWeeklyDuration),
        accountScopeID: accountScopeID,
        quotaID: "codex-weekly"
    )
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
