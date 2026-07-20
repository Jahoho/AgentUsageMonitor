import Foundation

public enum HeadroomAnalyzer {
    private static let resetCycleTolerance: TimeInterval = 5 * 60
    private static let materialCapacityIncrease = 0.02
    private static let minimumSampleCount = 3
    private static let longWindowThreshold: TimeInterval = 24 * 60 * 60
    private static let shortWindowMinimumCoverage: TimeInterval = 30 * 60
    private static let longWindowMinimumCoverage: TimeInterval = 6 * 60 * 60
    private static let shortWindowLookback: TimeInterval = 2 * 60 * 60
    private static let longWindowLookback: TimeInterval = 24 * 60 * 60
    private static let expectedSampleInterval: TimeInterval = 5 * 60
    private static let windyProjectedRemainingThreshold = 0.15

    public static func analyze(
        current: [QuotaObservation],
        history: [QuotaObservation],
        now: Date = Date()
    ) -> CapacityInsight? {
        let validCurrent = current.filter { observation in
            observation.remainingFraction.isFinite
                && (0...1).contains(observation.remainingFraction)
                && observation.resetAt > now
        }
        guard let firstCurrent = validCurrent.first else {
            return nil
        }

        let providerID = firstCurrent.providerID
        let accountScopeID = firstCurrent.accountScopeID
        var seenQuotaIDs = Set<String>()
        let orderedCurrent = validCurrent
            .filter {
                $0.providerID == providerID
                    && $0.accountScopeID == accountScopeID
                    && seenQuotaIDs.insert($0.quotaID).inserted
            }

        let windows = orderedCurrent.map { currentObservation in
            analyzeWindow(
                current: currentObservation,
                history: history,
                now: now
            )
        }
        let estimatedWindows = windows.filter { $0.confidence == .estimated }

        guard let constrainingWindow = estimatedWindows.min(by: isLessConstraining) else {
            return CapacityInsight(
                providerID: providerID,
                weather: .learning,
                constrainingQuotaID: windows.first?.quotaID,
                windows: windows,
                generatedAt: now,
                availabilityReason: .insufficientHistory
            )
        }

        return CapacityInsight(
            providerID: providerID,
            weather: constrainingWindow.weather,
            constrainingQuotaID: constrainingWindow.quotaID,
            windows: windows,
            generatedAt: now
        )
    }

    private static func analyzeWindow(
        current: QuotaObservation,
        history: [QuotaObservation],
        now: Date
    ) -> HeadroomWindowInsight {
        var observationsByDate: [Date: QuotaObservation] = [:]
        for observation in history where matchesCurrentSeries(observation, current: current) {
            observationsByDate[observation.capturedAt] = observation
        }
        observationsByDate[current.capturedAt] = current

        let allPoints = observationsByDate.values.sorted { $0.capturedAt < $1.capturedAt }
        let currentCyclePoints = pointsAfterLastCapacityIncrease(in: allPoints)
        let longestResetLead = currentCyclePoints
            .map { current.resetAt.timeIntervalSince($0.capturedAt) }
            .max() ?? 0
        let isLongWindow = longestResetLead > longWindowThreshold
        let minimumCoverage = isLongWindow
            ? longWindowMinimumCoverage
            : shortWindowMinimumCoverage
        let lookback = isLongWindow ? longWindowLookback : shortWindowLookback
        let recentCutoff = current.capturedAt.addingTimeInterval(-lookback)
        let recentPoints = currentCyclePoints.filter { $0.capturedAt >= recentCutoff }
        let trendPoints = hasEnoughCoverage(recentPoints, minimumCoverage: minimumCoverage)
            ? recentPoints
            : currentCyclePoints
        let coverageDuration = duration(of: trendPoints)
        let sampleCoverage = sampleCoverageFraction(
            sampleCount: trendPoints.count,
            duration: coverageDuration
        )

        guard hasEnoughCoverage(trendPoints, minimumCoverage: minimumCoverage),
              let first = trendPoints.first
        else {
            return HeadroomWindowInsight(
                quotaID: current.quotaID,
                weather: .learning,
                currentRemainingFraction: current.remainingFraction,
                projectedRemainingAtReset: nil,
                projectedExhaustionAt: nil,
                resetAt: current.resetAt,
                consumptionPerHour: nil,
                sampleCount: trendPoints.count,
                coverageDuration: coverageDuration,
                sampleCoverageFraction: sampleCoverage,
                availabilityReason: .insufficientHistory
            )
        }

        let minimumRemaining = trendPoints
            .map(\.remainingFraction)
            .min() ?? current.remainingFraction
        let consumedFraction = max(0, first.remainingFraction - minimumRemaining)
        let coverageHours = coverageDuration / 3_600
        let consumptionPerHour = coverageHours > 0 ? consumedFraction / coverageHours : 0
        let remainingHours = max(0, current.resetAt.timeIntervalSince(now) / 3_600)
        let projectedRemaining = current.remainingFraction - (consumptionPerHour * remainingHours)
        let projectedExhaustionAt: Date? = consumptionPerHour > 0
            ? now.addingTimeInterval((current.remainingFraction / consumptionPerHour) * 3_600)
            : nil
        let weather: CapacityWeather
        if projectedRemaining <= 0 {
            weather = .storm
        } else if projectedRemaining < windyProjectedRemainingThreshold {
            weather = .windy
        } else {
            weather = .clear
        }

        return HeadroomWindowInsight(
            quotaID: current.quotaID,
            weather: weather,
            currentRemainingFraction: current.remainingFraction,
            projectedRemainingAtReset: projectedRemaining,
            projectedExhaustionAt: projectedExhaustionAt,
            resetAt: current.resetAt,
            consumptionPerHour: consumptionPerHour,
            sampleCount: trendPoints.count,
            coverageDuration: coverageDuration,
            sampleCoverageFraction: sampleCoverage
        )
    }

    private static func matchesCurrentSeries(
        _ observation: QuotaObservation,
        current: QuotaObservation
    ) -> Bool {
        observation.providerID == current.providerID
            && observation.accountScopeID == current.accountScopeID
            && observation.quotaID == current.quotaID
            && observation.capturedAt <= current.capturedAt
            && abs(observation.resetAt.timeIntervalSince(current.resetAt)) <= resetCycleTolerance
    }

    private static func pointsAfterLastCapacityIncrease(
        in points: [QuotaObservation]
    ) -> [QuotaObservation] {
        guard points.count > 1 else {
            return points
        }

        var segmentStart = 0
        for index in 1..<points.count {
            let increase = points[index].remainingFraction - points[index - 1].remainingFraction
            if increase > materialCapacityIncrease {
                segmentStart = index
            }
        }
        return Array(points[segmentStart...])
    }

    private static func hasEnoughCoverage(
        _ points: [QuotaObservation],
        minimumCoverage: TimeInterval
    ) -> Bool {
        points.count >= minimumSampleCount && duration(of: points) >= minimumCoverage
    }

    private static func duration(of points: [QuotaObservation]) -> TimeInterval {
        guard let first = points.first, let last = points.last else {
            return 0
        }
        return max(0, last.capturedAt.timeIntervalSince(first.capturedAt))
    }

    private static func sampleCoverageFraction(
        sampleCount: Int,
        duration: TimeInterval
    ) -> Double {
        guard sampleCount > 0 else {
            return 0
        }
        let expectedCount = max(1, Int(duration / expectedSampleInterval) + 1)
        return min(1, Double(sampleCount) / Double(expectedCount))
    }

    private static func isLessConstraining(
        _ lhs: HeadroomWindowInsight,
        _ rhs: HeadroomWindowInsight
    ) -> Bool {
        let lhsRank = severityRank(lhs.weather)
        let rhsRank = severityRank(rhs.weather)
        if lhsRank != rhsRank {
            return lhsRank > rhsRank
        }
        return (lhs.projectedRemainingAtReset ?? 1) < (rhs.projectedRemainingAtReset ?? 1)
    }

    private static func severityRank(_ weather: CapacityWeather) -> Int {
        switch weather {
        case .storm:
            return 3
        case .windy:
            return 2
        case .clear:
            return 1
        case .learning, .fog:
            return 0
        }
    }
}
