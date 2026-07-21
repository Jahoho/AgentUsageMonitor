import Foundation

public enum WeeklySubscriptionReviewAvailabilityReason: String, Sendable {
    case currentQuotaUnavailable
    case accountScopeUnavailable
    case weeklyWindowUnavailable
    case historyUnavailable
    case insufficientCurrentCycle
}

public enum WeeklySubscriptionComparisonAvailabilityReason: String, Sendable {
    case noPreviousCycle
    case insufficientPreviousCoverage
    case noComparablePoint
}

public enum WeeklySubscriptionUsageScope: String, Sendable {
    case cycleToDate
    case observedSpan
}

public struct WeeklySubscriptionCycleSummary: Equatable, Sendable {
    public let quotaID: String
    public let resetAt: Date
    public let currentRemainingFraction: Double
    public let observedUsedFraction: Double
    public let sampleCount: Int
    public let coverageDuration: TimeInterval
    public let cycleCoverageFraction: Double?
    public let sampleCoverageFraction: Double
    public let usageScope: WeeklySubscriptionUsageScope

    public init(
        quotaID: String,
        resetAt: Date,
        currentRemainingFraction: Double,
        observedUsedFraction: Double,
        sampleCount: Int,
        coverageDuration: TimeInterval,
        cycleCoverageFraction: Double?,
        sampleCoverageFraction: Double,
        usageScope: WeeklySubscriptionUsageScope
    ) {
        self.quotaID = quotaID
        self.resetAt = resetAt
        self.currentRemainingFraction = currentRemainingFraction
        self.observedUsedFraction = observedUsedFraction
        self.sampleCount = sampleCount
        self.coverageDuration = coverageDuration
        self.cycleCoverageFraction = cycleCoverageFraction
        self.sampleCoverageFraction = sampleCoverageFraction
        self.usageScope = usageScope
    }
}

public struct WeeklySubscriptionComparison: Equatable, Sendable {
    /// Positive means the current cycle has more remaining capacity.
    public let remainingDifferenceFraction: Double
    public let previousRemainingFraction: Double
    public let matchedProgressDifference: TimeInterval

    public init(
        remainingDifferenceFraction: Double,
        previousRemainingFraction: Double,
        matchedProgressDifference: TimeInterval
    ) {
        self.remainingDifferenceFraction = remainingDifferenceFraction
        self.previousRemainingFraction = previousRemainingFraction
        self.matchedProgressDifference = matchedProgressDifference
    }
}

public struct WeeklySubscriptionReview: Equatable, Sendable {
    public let providerID: String
    public let currentCycle: WeeklySubscriptionCycleSummary?
    public let comparison: WeeklySubscriptionComparison?
    public let comparisonAvailabilityReason: WeeklySubscriptionComparisonAvailabilityReason?
    public let generatedAt: Date
    public let availabilityReason: WeeklySubscriptionReviewAvailabilityReason?

    public init(
        providerID: String,
        currentCycle: WeeklySubscriptionCycleSummary?,
        comparison: WeeklySubscriptionComparison?,
        comparisonAvailabilityReason: WeeklySubscriptionComparisonAvailabilityReason?,
        generatedAt: Date,
        availabilityReason: WeeklySubscriptionReviewAvailabilityReason? = nil
    ) {
        self.providerID = providerID
        self.currentCycle = currentCycle
        self.comparison = comparison
        self.comparisonAvailabilityReason = comparisonAvailabilityReason
        self.generatedAt = generatedAt
        self.availabilityReason = availabilityReason
    }

    public var confidence: UsageConfidence {
        currentCycle == nil ? .unavailable : .observed
    }

    public static func unavailable(
        providerID: String,
        reason: WeeklySubscriptionReviewAvailabilityReason,
        generatedAt: Date
    ) -> WeeklySubscriptionReview {
        WeeklySubscriptionReview(
            providerID: providerID,
            currentCycle: nil,
            comparison: nil,
            comparisonAvailabilityReason: nil,
            generatedAt: generatedAt,
            availabilityReason: reason
        )
    }
}
