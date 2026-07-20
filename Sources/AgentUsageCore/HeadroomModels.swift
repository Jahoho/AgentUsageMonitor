import Foundation

public enum CapacityWeather: String, Codable, CaseIterable, Sendable {
    case clear
    case windy
    case storm
    case fog
    case learning
}

public enum HeadroomAvailabilityReason: String, Codable, Sendable {
    case currentQuotaUnavailable
    case accountScopeUnavailable
    case resetUnavailable
    case historyUnavailable
    case insufficientHistory
}

public struct HeadroomWindowInsight: Identifiable, Equatable, Sendable {
    public var id: String { quotaID }

    public let quotaID: String
    public let weather: CapacityWeather
    public let currentRemainingFraction: Double
    public let projectedRemainingAtReset: Double?
    public let projectedExhaustionAt: Date?
    public let resetAt: Date
    public let consumptionPerHour: Double?
    public let sampleCount: Int
    public let coverageDuration: TimeInterval
    public let sampleCoverageFraction: Double
    public let availabilityReason: HeadroomAvailabilityReason?

    public init(
        quotaID: String,
        weather: CapacityWeather,
        currentRemainingFraction: Double,
        projectedRemainingAtReset: Double?,
        projectedExhaustionAt: Date?,
        resetAt: Date,
        consumptionPerHour: Double?,
        sampleCount: Int,
        coverageDuration: TimeInterval,
        sampleCoverageFraction: Double,
        availabilityReason: HeadroomAvailabilityReason? = nil
    ) {
        self.quotaID = quotaID
        self.weather = weather
        self.currentRemainingFraction = currentRemainingFraction
        self.projectedRemainingAtReset = projectedRemainingAtReset
        self.projectedExhaustionAt = projectedExhaustionAt
        self.resetAt = resetAt
        self.consumptionPerHour = consumptionPerHour
        self.sampleCount = sampleCount
        self.coverageDuration = coverageDuration
        self.sampleCoverageFraction = sampleCoverageFraction
        self.availabilityReason = availabilityReason
    }

    public var confidence: UsageConfidence {
        switch weather {
        case .clear, .windy, .storm:
            return .estimated
        case .fog, .learning:
            return .unavailable
        }
    }
}

public struct CapacityInsight: Equatable, Sendable {
    public let providerID: String
    public let weather: CapacityWeather
    public let constrainingQuotaID: String?
    public let windows: [HeadroomWindowInsight]
    public let generatedAt: Date
    public let availabilityReason: HeadroomAvailabilityReason?

    public init(
        providerID: String,
        weather: CapacityWeather,
        constrainingQuotaID: String?,
        windows: [HeadroomWindowInsight],
        generatedAt: Date,
        availabilityReason: HeadroomAvailabilityReason? = nil
    ) {
        self.providerID = providerID
        self.weather = weather
        self.constrainingQuotaID = constrainingQuotaID
        self.windows = windows
        self.generatedAt = generatedAt
        self.availabilityReason = availabilityReason
    }

    public var confidence: UsageConfidence {
        switch weather {
        case .clear, .windy, .storm:
            return .estimated
        case .fog, .learning:
            return .unavailable
        }
    }

    public static func unavailable(
        providerID: String,
        reason: HeadroomAvailabilityReason,
        generatedAt: Date
    ) -> CapacityInsight {
        CapacityInsight(
            providerID: providerID,
            weather: reason == .insufficientHistory ? .learning : .fog,
            constrainingQuotaID: nil,
            windows: [],
            generatedAt: generatedAt,
            availabilityReason: reason
        )
    }
}
