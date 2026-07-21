import Foundation

public enum WeeklySubscriptionReviewAvailabilityReason: String, Sendable {
    case currentQuotaUnavailable
    case accountScopeUnavailable
    case weeklyWindowUnavailable
    case historyUnavailable
    case noCompletedCycle
    case insufficientCompletedCycleCoverage
}

public enum WeeklySubscriptionRhythmPattern: String, Sendable {
    case quiet
    case concentrated
    case steady
    case mixed
}

public struct WeeklySubscriptionRhythmSummary: Equatable, Sendable {
    public let pattern: WeeklySubscriptionRhythmPattern
    public let activeDayCount: Int
    /// Uses the `Calendar.Component.weekday` convention: Sunday is 1 and Saturday is 7.
    public let peakWeekday: Int?
    public let topTwoDayUseFraction: Double
    public let attributedUseFraction: Double

    public init(
        pattern: WeeklySubscriptionRhythmPattern,
        activeDayCount: Int,
        peakWeekday: Int?,
        topTwoDayUseFraction: Double,
        attributedUseFraction: Double
    ) {
        self.pattern = pattern
        self.activeDayCount = activeDayCount
        self.peakWeekday = peakWeekday
        self.topTwoDayUseFraction = topTwoDayUseFraction
        self.attributedUseFraction = attributedUseFraction
    }
}

public struct WeeklySubscriptionCompletedCycleSummary: Equatable, Sendable {
    public let quotaID: String
    public let startedAt: Date
    public let resetAt: Date
    public let endingRemainingFraction: Double
    public let lowestRemainingFraction: Double
    public let observedUsedFraction: Double
    public let sampleCount: Int
    public let sampleCoverageFraction: Double
    public let endObservationLead: TimeInterval
    public let rhythm: WeeklySubscriptionRhythmSummary?

    public init(
        quotaID: String,
        startedAt: Date,
        resetAt: Date,
        endingRemainingFraction: Double,
        lowestRemainingFraction: Double,
        observedUsedFraction: Double,
        sampleCount: Int,
        sampleCoverageFraction: Double,
        endObservationLead: TimeInterval,
        rhythm: WeeklySubscriptionRhythmSummary?
    ) {
        self.quotaID = quotaID
        self.startedAt = startedAt
        self.resetAt = resetAt
        self.endingRemainingFraction = endingRemainingFraction
        self.lowestRemainingFraction = lowestRemainingFraction
        self.observedUsedFraction = observedUsedFraction
        self.sampleCount = sampleCount
        self.sampleCoverageFraction = sampleCoverageFraction
        self.endObservationLead = endObservationLead
        self.rhythm = rhythm
    }
}

public struct WeeklySubscriptionBaselineComparison: Equatable, Sendable {
    /// Positive means the completed cycle used more quota than its personal baseline.
    public let usedDifferenceFraction: Double
    public let medianUsedFraction: Double
    public let comparisonCycleCount: Int

    public init(
        usedDifferenceFraction: Double,
        medianUsedFraction: Double,
        comparisonCycleCount: Int
    ) {
        self.usedDifferenceFraction = usedDifferenceFraction
        self.medianUsedFraction = medianUsedFraction
        self.comparisonCycleCount = comparisonCycleCount
    }
}

public enum WeeklySubscriptionPlanFitPattern: String, Sendable {
    case ampleHeadroom
    case frequentPressure
    case mixed
}

public struct WeeklySubscriptionPlanFitSummary: Equatable, Sendable {
    public let pattern: WeeklySubscriptionPlanFitPattern
    public let evaluatedCycleCount: Int
    public let ampleHeadroomCycleCount: Int
    public let nearLimitCycleCount: Int

    public init(
        pattern: WeeklySubscriptionPlanFitPattern,
        evaluatedCycleCount: Int,
        ampleHeadroomCycleCount: Int,
        nearLimitCycleCount: Int
    ) {
        self.pattern = pattern
        self.evaluatedCycleCount = evaluatedCycleCount
        self.ampleHeadroomCycleCount = ampleHeadroomCycleCount
        self.nearLimitCycleCount = nearLimitCycleCount
    }
}

public struct WeeklySubscriptionReview: Equatable, Sendable {
    public let providerID: String
    /// Identifies the current Official cycle used to scope and refresh this historical recap.
    public let currentResetAt: Date?
    public let completedCycle: WeeklySubscriptionCompletedCycleSummary?
    public let baselineComparison: WeeklySubscriptionBaselineComparison?
    public let planFit: WeeklySubscriptionPlanFitSummary?
    public let eligibleCompletedCycleCount: Int
    public let generatedAt: Date
    public let availabilityReason: WeeklySubscriptionReviewAvailabilityReason?

    public init(
        providerID: String,
        currentResetAt: Date?,
        completedCycle: WeeklySubscriptionCompletedCycleSummary?,
        baselineComparison: WeeklySubscriptionBaselineComparison?,
        planFit: WeeklySubscriptionPlanFitSummary?,
        eligibleCompletedCycleCount: Int,
        generatedAt: Date,
        availabilityReason: WeeklySubscriptionReviewAvailabilityReason? = nil
    ) {
        self.providerID = providerID
        self.currentResetAt = currentResetAt
        self.completedCycle = completedCycle
        self.baselineComparison = baselineComparison
        self.planFit = planFit
        self.eligibleCompletedCycleCount = eligibleCompletedCycleCount
        self.generatedAt = generatedAt
        self.availabilityReason = availabilityReason
    }

    public var confidence: UsageConfidence {
        completedCycle == nil ? .unavailable : .observed
    }

    public static func unavailable(
        providerID: String,
        reason: WeeklySubscriptionReviewAvailabilityReason,
        generatedAt: Date,
        currentResetAt: Date? = nil
    ) -> WeeklySubscriptionReview {
        WeeklySubscriptionReview(
            providerID: providerID,
            currentResetAt: currentResetAt,
            completedCycle: nil,
            baselineComparison: nil,
            planFit: nil,
            eligibleCompletedCycleCount: 0,
            generatedAt: generatedAt,
            availabilityReason: reason
        )
    }
}
