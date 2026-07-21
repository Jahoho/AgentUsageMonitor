import Foundation

public enum QuotaProjectionAvailabilityReason: String, Sendable {
    case currentQuotaUnavailable
    case accountScopeUnavailable
    case resetUnavailable
    case historyUnavailable
    case insufficientHistory
    case sparseHistory
    case unstableTrend
}

public enum QuotaProjectionOutcome: String, Sendable {
    case remainingAtReset
    case mayExhaustBeforeReset
    case likelyExhaustsBeforeReset
}

public struct QuotaWindowProjection: Identifiable, Equatable, Sendable {
    public static let maximumPreciseForecastError = 0.20

    public var id: String { quotaID }

    public let quotaID: String
    public let currentRemainingFraction: Double
    public let projectedRemainingAtReset: Double?
    public let projectedRemainingLowerBound: Double?
    public let projectedRemainingUpperBound: Double?
    public let projectedExhaustionAt: Date?
    public let resetAt: Date
    public let consumptionPerHour: Double?
    public let sampleCount: Int
    public let coverageDuration: TimeInterval
    public let sampleCoverageFraction: Double
    public let forecastErrorFraction: Double?
    public let availabilityReason: QuotaProjectionAvailabilityReason?

    public init(
        quotaID: String,
        currentRemainingFraction: Double,
        projectedRemainingAtReset: Double?,
        projectedRemainingLowerBound: Double?,
        projectedRemainingUpperBound: Double?,
        projectedExhaustionAt: Date?,
        resetAt: Date,
        consumptionPerHour: Double?,
        sampleCount: Int,
        coverageDuration: TimeInterval,
        sampleCoverageFraction: Double,
        forecastErrorFraction: Double?,
        availabilityReason: QuotaProjectionAvailabilityReason? = nil
    ) {
        self.quotaID = quotaID
        self.currentRemainingFraction = currentRemainingFraction
        self.projectedRemainingAtReset = projectedRemainingAtReset
        self.projectedRemainingLowerBound = projectedRemainingLowerBound
        self.projectedRemainingUpperBound = projectedRemainingUpperBound
        self.projectedExhaustionAt = projectedExhaustionAt
        self.resetAt = resetAt
        self.consumptionPerHour = consumptionPerHour
        self.sampleCount = sampleCount
        self.coverageDuration = coverageDuration
        self.sampleCoverageFraction = sampleCoverageFraction
        self.forecastErrorFraction = forecastErrorFraction
        self.availabilityReason = availabilityReason
    }

    public var confidence: UsageConfidence {
        guard projectedRemainingAtReset != nil,
              projectedRemainingLowerBound != nil,
              projectedRemainingUpperBound != nil,
              availabilityReason == nil
        else {
            return .unavailable
        }
        return .estimated
    }

    public var outcome: QuotaProjectionOutcome? {
        guard let lowerBound = projectedRemainingLowerBound,
              let upperBound = projectedRemainingUpperBound
        else {
            return nil
        }
        if upperBound <= 0 {
            return .likelyExhaustsBeforeReset
        }
        if lowerBound <= 0 {
            return .mayExhaustBeforeReset
        }
        return .remainingAtReset
    }
}

public struct QuotaProjection: Equatable, Sendable {
    public let providerID: String
    public let constrainingQuotaID: String?
    public let windows: [QuotaWindowProjection]
    public let generatedAt: Date
    public let availabilityReason: QuotaProjectionAvailabilityReason?

    public init(
        providerID: String,
        constrainingQuotaID: String?,
        windows: [QuotaWindowProjection],
        generatedAt: Date,
        availabilityReason: QuotaProjectionAvailabilityReason? = nil
    ) {
        self.providerID = providerID
        self.constrainingQuotaID = constrainingQuotaID
        self.windows = windows
        self.generatedAt = generatedAt
        self.availabilityReason = availabilityReason
    }

    public var constrainingWindow: QuotaWindowProjection? {
        guard let constrainingQuotaID else {
            return nil
        }
        return windows.first { $0.quotaID == constrainingQuotaID }
    }

    public var confidence: UsageConfidence {
        constrainingWindow?.confidence ?? .unavailable
    }

    public static func unavailable(
        providerID: String,
        reason: QuotaProjectionAvailabilityReason,
        generatedAt: Date
    ) -> QuotaProjection {
        QuotaProjection(
            providerID: providerID,
            constrainingQuotaID: nil,
            windows: [],
            generatedAt: generatedAt,
            availabilityReason: reason
        )
    }
}
