import Foundation

public enum QuotaProjectionAnalyzer {
    private static let resetCycleTolerance: TimeInterval = 5 * 60
    private static let materialCapacityIncrease = 0.02
    private static let transientSpikeThreshold = 0.02
    private static let minimumSampleCount = 5
    private static let longWindowThreshold: TimeInterval = 24 * 60 * 60
    private static let shortWindowMinimumCoverage: TimeInterval = 30 * 60
    private static let longWindowMinimumCoverage: TimeInterval = 6 * 60 * 60
    private static let shortWindowLookback: TimeInterval = 3 * 60 * 60
    private static let longWindowLookback: TimeInterval = 36 * 60 * 60
    private static let shortRecentHorizon: TimeInterval = 45 * 60
    private static let longRecentHorizon: TimeInterval = 6 * 60 * 60
    private static let expectedSampleInterval: TimeInterval = 5 * 60
    private static let minimumSampleCoverage = 0.15
    private static let shortMaximumGap: TimeInterval = 45 * 60
    private static let longRecentContinuityGap: TimeInterval = 4 * 60 * 60
    private static let minimumForecastError = 0.01

    public static func analyze(
        current: [QuotaObservation],
        history: [QuotaObservation],
        now: Date = Date()
    ) -> QuotaProjection? {
        let validCurrent = current.filter { observation in
            isValid(observation) && observation.resetAt > now
        }
        guard let firstCurrent = validCurrent.first else {
            return nil
        }

        let providerID = firstCurrent.providerID
        let accountScopeID = firstCurrent.accountScopeID
        var seenQuotaIDs = Set<String>()
        let orderedCurrent = validCurrent.filter { observation in
            observation.providerID == providerID
                && observation.accountScopeID == accountScopeID
                && seenQuotaIDs.insert(observation.quotaID).inserted
        }

        let windows = orderedCurrent.map { observation in
            analyzeWindow(current: observation, history: history, now: now)
        }
        let estimatedWindows = windows.filter { $0.confidence == .estimated }
        guard let constrainingWindow = estimatedWindows.min(by: isLessConstraining) else {
            return QuotaProjection(
                providerID: providerID,
                constrainingQuotaID: nil,
                windows: windows,
                generatedAt: now,
                availabilityReason: aggregateUnavailableReason(windows)
            )
        }

        return QuotaProjection(
            providerID: providerID,
            constrainingQuotaID: constrainingWindow.quotaID,
            windows: windows,
            generatedAt: now
        )
    }

    private static func analyzeWindow(
        current: QuotaObservation,
        history: [QuotaObservation],
        now: Date
    ) -> QuotaWindowProjection {
        var observationsByDate: [Date: QuotaObservation] = [:]
        for observation in history where matchesCurrentSeries(observation, current: current) {
            observationsByDate[observation.capturedAt] = observation
        }
        observationsByDate[current.capturedAt] = current

        let orderedPoints = observationsByDate.values
            .sorted { $0.capturedAt < $1.capturedAt }
        let cleanedPoints = removingTransientSpikes(from: orderedPoints)
        let currentCyclePoints = pointsAfterLastCapacityIncrease(in: cleanedPoints)
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
        let selectedPoints = hasBasicCoverage(recentPoints, minimumCoverage: minimumCoverage)
            ? recentPoints
            : currentCyclePoints
        let coverageDuration = duration(of: selectedPoints)
        let sampleCoverage = sampleCoverageFraction(
            sampleCount: selectedPoints.count,
            duration: coverageDuration
        )

        guard hasBasicCoverage(selectedPoints, minimumCoverage: minimumCoverage) else {
            return unavailableWindow(
                current: current,
                points: selectedPoints,
                sampleCoverage: sampleCoverage,
                reason: .insufficientHistory
            )
        }

        guard sampleCoverage >= minimumSampleCoverage else {
            return unavailableWindow(
                current: current,
                points: selectedPoints,
                sampleCoverage: sampleCoverage,
                reason: .sparseHistory
            )
        }
        if isLongWindow == false,
           maximumGap(in: selectedPoints) > shortMaximumGap {
            return unavailableWindow(
                current: current,
                points: selectedPoints,
                sampleCoverage: sampleCoverage,
                reason: .sparseHistory
            )
        }

        let trendPoints = monotonicTrendPoints(from: selectedPoints)
        guard let fullFit = robustFit(points: trendPoints, isLongWindow: isLongWindow) else {
            return unavailableWindow(
                current: current,
                points: selectedPoints,
                sampleCoverage: sampleCoverage,
                reason: .unstableTrend
            )
        }

        let fittedRate = max(0, -fullFit.slope)
        let broadRate = isLongWindow
            ? elapsedConsumptionRate(points: trendPoints) ?? fittedRate
            : fittedRate
        let recentTrendPoints = isLongWindow
            ? pointsAfterLastGap(
                in: trendPoints,
                maximumGap: longRecentContinuityGap
            )
            : trendPoints
        let recentRate = recentConsumptionRate(
            points: recentTrendPoints,
            isLongWindow: isLongWindow
        )
        let remainingHours = max(0, current.resetAt.timeIntervalSince(now) / 3_600)
        let consumptionRate: Double
        let weightedPaceShift: Double
        if let recentRate {
            // A short forecast can react quickly to a burst. Farther forecasts
            // shrink toward the broader trend instead of extending one burst.
            let distanceAdjustedWeight = 0.65 / sqrt(max(1, remainingHours))
            let recentWeight = isLongWindow
                ? min(0.65, distanceAdjustedWeight)
                : max(0.2, min(0.65, distanceAdjustedWeight))
            consumptionRate = (recentRate * recentWeight)
                + (broadRate * (1 - recentWeight))
            weightedPaceShift = abs(recentRate - broadRate) * recentWeight
        } else {
            consumptionRate = broadRate
            weightedPaceShift = 0
        }

        let validationError = holdoutValidationError(
            points: trendPoints,
            isLongWindow: isLongWindow
        ) ?? 0
        let projectedRemaining = current.remainingFraction - (consumptionRate * remainingHours)
        let rateError = max(fullFit.slopeStandardError * 1.64, weightedPaceShift * 0.5)
        let fitError = max(fullFit.medianAbsoluteResidual * 1.64, validationError)
        let processError = consumptionProcessError(
            points: trendPoints,
            isLongWindow: isLongWindow,
            consumptionRate: consumptionRate,
            remainingHours: remainingHours
        )
        let forecastError = max(
            minimumForecastError,
            fitError + (rateError * remainingHours),
            processError
        )
        let lowerBound = max(-1, projectedRemaining - forecastError)
        let upperBound = min(current.remainingFraction, projectedRemaining + forecastError)
        let stableLongExhaustion = isLongWindow && upperBound <= 0

        guard forecastError.isFinite,
              forecastError <= QuotaWindowProjection.maximumPreciseForecastError
                || stableLongExhaustion
        else {
            return unavailableWindow(
                current: current,
                points: selectedPoints,
                sampleCoverage: sampleCoverage,
                reason: .unstableTrend
            )
        }

        let exhaustionAt: Date? = consumptionRate > 0
            ? now.addingTimeInterval((current.remainingFraction / consumptionRate) * 3_600)
            : nil

        return QuotaWindowProjection(
            quotaID: current.quotaID,
            currentRemainingFraction: current.remainingFraction,
            projectedRemainingAtReset: projectedRemaining,
            projectedRemainingLowerBound: lowerBound,
            projectedRemainingUpperBound: upperBound,
            projectedExhaustionAt: exhaustionAt,
            resetAt: current.resetAt,
            consumptionPerHour: consumptionRate,
            sampleCount: selectedPoints.count,
            coverageDuration: coverageDuration,
            sampleCoverageFraction: sampleCoverage,
            forecastErrorFraction: forecastError
        )
    }

    private static func unavailableWindow(
        current: QuotaObservation,
        points: [QuotaObservation],
        sampleCoverage: Double,
        reason: QuotaProjectionAvailabilityReason
    ) -> QuotaWindowProjection {
        QuotaWindowProjection(
            quotaID: current.quotaID,
            currentRemainingFraction: current.remainingFraction,
            projectedRemainingAtReset: nil,
            projectedRemainingLowerBound: nil,
            projectedRemainingUpperBound: nil,
            projectedExhaustionAt: nil,
            resetAt: current.resetAt,
            consumptionPerHour: nil,
            sampleCount: points.count,
            coverageDuration: duration(of: points),
            sampleCoverageFraction: sampleCoverage,
            forecastErrorFraction: nil,
            availabilityReason: reason
        )
    }

    private static func matchesCurrentSeries(
        _ observation: QuotaObservation,
        current: QuotaObservation
    ) -> Bool {
        isValid(observation)
            && observation.providerID == current.providerID
            && observation.accountScopeID == current.accountScopeID
            && observation.quotaID == current.quotaID
            && observation.capturedAt <= current.capturedAt
            && abs(observation.resetAt.timeIntervalSince(current.resetAt)) <= resetCycleTolerance
    }

    private static func isValid(_ observation: QuotaObservation) -> Bool {
        observation.remainingFraction.isFinite
            && (0...1).contains(observation.remainingFraction)
            && observation.resetAt > observation.capturedAt
    }

    /// Removes a one-sample jump that immediately returns to the prior level.
    /// Sustained drops and sustained capacity increases remain untouched.
    private static func removingTransientSpikes(
        from points: [QuotaObservation]
    ) -> [QuotaObservation] {
        guard points.count >= 3 else {
            return points
        }

        var retained = [points[0]]
        for index in 1..<(points.count - 1) {
            let previous = points[index - 1].remainingFraction
            let current = points[index].remainingFraction
            let next = points[index + 1].remainingFraction
            let neighborsAreStable = abs(previous - next) <= transientSpikeThreshold
            let currentIsIsolated = abs(current - previous) > transientSpikeThreshold
                && abs(current - next) > transientSpikeThreshold
            if neighborsAreStable && currentIsIsolated {
                continue
            }
            retained.append(points[index])
        }
        retained.append(points[points.count - 1])
        return retained
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

    /// Quota remaining should not rise inside one reset cycle. Small upward
    /// movements are treated as source noise after material increases are split.
    private static func monotonicTrendPoints(
        from points: [QuotaObservation]
    ) -> [TrendPoint] {
        guard let first = points.first else {
            return []
        }

        var runningMinimum = first.remainingFraction
        return points.map { point in
            runningMinimum = min(runningMinimum, point.remainingFraction)
            return TrendPoint(capturedAt: point.capturedAt, remainingFraction: runningMinimum)
        }
    }

    private static func robustFit(
        points: [TrendPoint],
        isLongWindow: Bool
    ) -> LinearFit? {
        guard points.count >= 2, let latest = points.last?.capturedAt else {
            return nil
        }

        let halfLifeHours = isLongWindow ? 12.0 : 2.0
        let baseWeights = points.map { point in
            let ageHours = max(0, latest.timeIntervalSince(point.capturedAt) / 3_600)
            return pow(0.5, ageHours / halfLifeHours)
        }
        guard let initialFit = weightedLinearFit(points: points, weights: baseWeights) else {
            return nil
        }

        let residuals = points.map { point in
            point.remainingFraction - initialFit.prediction(at: point.capturedAt)
        }
        let residualCenter = median(residuals)
        let medianDeviation = median(residuals.map { abs($0 - residualCenter) })
        let huberThreshold = max(0.002, medianDeviation * 1.4826 * 1.5)
        let robustWeights = zip(baseWeights, residuals).map { baseWeight, residual in
            let deviation = abs(residual - residualCenter)
            guard deviation > huberThreshold else {
                return baseWeight
            }
            return baseWeight * (huberThreshold / deviation)
        }
        return weightedLinearFit(points: points, weights: robustWeights)
    }

    private static func weightedLinearFit(
        points: [TrendPoint],
        weights: [Double]
    ) -> LinearFit? {
        guard points.count == weights.count,
              let origin = points.first?.capturedAt
        else {
            return nil
        }

        let xValues = points.map { $0.capturedAt.timeIntervalSince(origin) / 3_600 }
        let weightSum = weights.reduce(0, +)
        guard weightSum > 0 else {
            return nil
        }
        let xMean = zip(xValues, weights).reduce(0) { partial, pair in
            partial + (pair.0 * pair.1)
        } / weightSum
        let yMean = zip(points, weights).reduce(0) { partial, pair in
            partial + (pair.0.remainingFraction * pair.1)
        } / weightSum
        let denominator = zip(xValues, weights).reduce(0) { partial, pair in
            partial + (pair.1 * pow(pair.0 - xMean, 2))
        }
        guard denominator > 0 else {
            return nil
        }
        let numerator = zip(zip(xValues, points), weights).reduce(0) { partial, pair in
            let x = pair.0.0
            let point = pair.0.1
            let weight = pair.1
            return partial + (weight * (x - xMean) * (point.remainingFraction - yMean))
        }
        let slope = numerator / denominator
        let intercept = yMean - (slope * xMean)
        let residuals = zip(xValues, points).map { x, point in
            point.remainingFraction - (intercept + (slope * x))
        }
        let weightedSquaredError = zip(residuals, weights).reduce(0) { partial, pair in
            partial + (pair.1 * pair.0 * pair.0)
        }
        let effectiveCountNumerator = weightSum * weightSum
        let effectiveCountDenominator = weights.reduce(0) { $0 + ($1 * $1) }
        let effectiveCount = effectiveCountDenominator > 0
            ? effectiveCountNumerator / effectiveCountDenominator
            : Double(points.count)
        let degreesOfFreedom = max(1, effectiveCount - 2)
        let residualVariance = weightedSquaredError / degreesOfFreedom

        return LinearFit(
            origin: origin,
            intercept: intercept,
            slope: slope,
            slopeStandardError: sqrt(max(0, residualVariance / denominator)),
            medianAbsoluteResidual: median(residuals.map { abs($0) })
        )
    }

    private static func recentConsumptionRate(
        points: [TrendPoint],
        isLongWindow: Bool
    ) -> Double? {
        guard let latest = points.last?.capturedAt else {
            return nil
        }
        let horizon = isLongWindow ? longRecentHorizon : shortRecentHorizon
        let cutoff = latest.addingTimeInterval(-horizon)
        let recentPoints = points.filter { $0.capturedAt >= cutoff }
        guard recentPoints.count >= minimumSampleCount,
              duration(of: recentPoints) >= horizon * 0.5,
              let fit = robustFit(points: recentPoints, isLongWindow: isLongWindow)
        else {
            return nil
        }
        return max(0, -fit.slope)
    }

    /// Long-window pace is anchored to elapsed calendar time so normal idle
    /// periods, including overnight gaps, remain part of the weekly baseline.
    private static func elapsedConsumptionRate(points: [TrendPoint]) -> Double? {
        guard let first = points.first,
              let last = points.last
        else {
            return nil
        }
        let elapsedHours = last.capturedAt.timeIntervalSince(first.capturedAt) / 3_600
        guard elapsedHours > 0 else {
            return nil
        }
        return max(0, (first.remainingFraction - last.remainingFraction) / elapsedHours)
    }

    /// Quota sources often move in discrete steps rather than continuously.
    /// Treating those steps as recurring events gives the range room for
    /// ordinary burst timing without changing the point estimate.
    private static func consumptionProcessError(
        points: [TrendPoint],
        isLongWindow: Bool,
        consumptionRate: Double,
        remainingHours: Double
    ) -> Double {
        let drops = zip(points, points.dropFirst()).compactMap { previous, next in
            let drop = previous.remainingFraction - next.remainingFraction
            return drop > 0 ? drop : nil
        }
        guard let latest = points.last?.capturedAt,
              drops.isEmpty == false
        else {
            return 0
        }

        let typicalStep = min(0.05, max(0.005, median(drops)))
        let bucketDuration: TimeInterval = isLongWindow ? 2 * 3_600 : 30 * 60
        let bucketCount = max(2, Int(ceil(duration(of: points) / bucketDuration)))
        var bucketConsumption = Array(repeating: 0.0, count: bucketCount)
        for (previous, next) in zip(points, points.dropFirst()) {
            let drop = max(0, previous.remainingFraction - next.remainingFraction)
            guard drop > 0 else {
                continue
            }
            let newerAge = max(0, latest.timeIntervalSince(next.capturedAt))
            let olderAge = max(newerAge, latest.timeIntervalSince(previous.capturedAt))
            let newerBucket = min(bucketCount - 1, Int(newerAge / bucketDuration))
            let intervalDuration = olderAge - newerAge
            guard intervalDuration > 0 else {
                bucketConsumption[newerBucket] += drop
                continue
            }

            let oldestIncludedAge = max(newerAge, olderAge.nextDown)
            let olderBucket = min(bucketCount - 1, Int(oldestIncludedAge / bucketDuration))
            for bucketIndex in newerBucket...olderBucket {
                let bucketStart = Double(bucketIndex) * bucketDuration
                let bucketEnd = bucketStart + bucketDuration
                let overlap = max(
                    0,
                    min(olderAge, bucketEnd) - max(newerAge, bucketStart)
                )
                bucketConsumption[bucketIndex] += drop * (overlap / intervalDuration)
            }
        }

        let meanBucketConsumption = bucketConsumption.reduce(0, +)
            / Double(bucketConsumption.count)
        guard meanBucketConsumption > 0 else {
            return 0
        }
        let bucketVariance = bucketConsumption.reduce(0) { partial, consumption in
            partial + pow(consumption - meanBucketConsumption, 2)
        } / Double(max(1, bucketConsumption.count - 1))
        let eventVariance = meanBucketConsumption * typicalStep
        let dispersion = eventVariance > 0
            ? min(16, max(0.25, bucketVariance / eventVariance))
            : 0.25
        let projectedConsumption = max(0, consumptionRate * remainingHours)
        let eventTimingError = 1.28
            * sqrt(projectedConsumption * typicalStep * dispersion)

        // Fit and holdout errors already scale average-rate uncertainty across
        // the full forecast. Session timing varies inside a day, so this
        // separate behavioral term is capped at one daily cycle instead of
        // extending one day's hour-to-hour variance across several days.
        let bucketHours = bucketDuration / 3_600
        let effectiveBucketCount = max(1, Double(bucketConsumption.count) / 2)
        let paceStandardError = sqrt(bucketVariance)
            / bucketHours
            / sqrt(effectiveBucketCount)
        let behavioralHorizon = min(remainingHours, 24)
        let behavioralPaceError = 1.28 * paceStandardError * behavioralHorizon
        return eventTimingError + behavioralPaceError
    }

    /// Uses the first 70% of a trend to predict its held-out tail. This makes
    /// the displayed range respond to actual recent forecast error, not only fit.
    private static func holdoutValidationError(
        points: [TrendPoint],
        isLongWindow: Bool
    ) -> Double? {
        guard points.count >= 8 else {
            return nil
        }
        let splitIndex = min(points.count - 2, max(5, Int(Double(points.count) * 0.7)))
        let training = Array(points[..<splitIndex])
        let validation = Array(points[splitIndex...])
        guard let fit = robustFit(points: training, isLongWindow: isLongWindow) else {
            return nil
        }
        return median(validation.map { point in
            abs(point.remainingFraction - fit.prediction(at: point.capturedAt))
        })
    }

    private static func hasBasicCoverage(
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

    private static func duration(of points: [TrendPoint]) -> TimeInterval {
        guard let first = points.first, let last = points.last else {
            return 0
        }
        return max(0, last.capturedAt.timeIntervalSince(first.capturedAt))
    }

    private static func maximumGap(in points: [QuotaObservation]) -> TimeInterval {
        guard points.count > 1 else {
            return .infinity
        }
        return zip(points, points.dropFirst())
            .map { current, next in
                max(0, next.capturedAt.timeIntervalSince(current.capturedAt))
            }
            .max() ?? .infinity
    }

    /// Long quota windows commonly contain an overnight sampling gap. The
    /// endpoints still describe total quota movement and remain useful for the
    /// broad trend, but recent pace must not bridge that unobserved interval.
    private static func pointsAfterLastGap(
        in points: [TrendPoint],
        maximumGap: TimeInterval
    ) -> [TrendPoint] {
        guard points.count > 1 else {
            return points
        }

        var segmentStart = 0
        for index in 1..<points.count {
            let gap = points[index].capturedAt.timeIntervalSince(points[index - 1].capturedAt)
            if gap > maximumGap {
                segmentStart = index
            }
        }
        return Array(points[segmentStart...])
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
        _ lhs: QuotaWindowProjection,
        _ rhs: QuotaWindowProjection
    ) -> Bool {
        let lhsLowerBound = lhs.projectedRemainingLowerBound
            ?? lhs.projectedRemainingAtReset
            ?? 1
        let rhsLowerBound = rhs.projectedRemainingLowerBound
            ?? rhs.projectedRemainingAtReset
            ?? 1
        if lhsLowerBound != rhsLowerBound {
            return lhsLowerBound < rhsLowerBound
        }
        return (lhs.projectedRemainingAtReset ?? 1) < (rhs.projectedRemainingAtReset ?? 1)
    }

    private static func aggregateUnavailableReason(
        _ windows: [QuotaWindowProjection]
    ) -> QuotaProjectionAvailabilityReason {
        if windows.contains(where: { $0.availabilityReason == .unstableTrend }) {
            return .unstableTrend
        }
        if windows.contains(where: { $0.availabilityReason == .sparseHistory }) {
            return .sparseHistory
        }
        return .insufficientHistory
    }

    private static func median(_ values: [Double]) -> Double {
        guard values.isEmpty == false else {
            return 0
        }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}

private struct TrendPoint {
    let capturedAt: Date
    let remainingFraction: Double
}

private struct LinearFit {
    let origin: Date
    let intercept: Double
    let slope: Double
    let slopeStandardError: Double
    let medianAbsoluteResidual: Double

    func prediction(at date: Date) -> Double {
        let elapsedHours = date.timeIntervalSince(origin) / 3_600
        return intercept + (slope * elapsedHours)
    }
}
