import Foundation

/// Normalizes historical Codex window ids without rewriting the protected JSONL file.
///
/// Older builds labeled every primary window as `codex-session`, even when the
/// official duration was weekly. A reset lead above one day cannot be a five-hour
/// session window, so every sample in that reset-time cluster can be read as weekly.
public enum CodexQuotaObservationNormalizer {
    public static let resetClusterTolerance: TimeInterval = 5 * 60
    public static let longWindowLeadThreshold: TimeInterval = 24 * 60 * 60

    public static func normalize(_ observations: [QuotaObservation]) -> [QuotaObservation] {
        let legacyIndices = observations.indices.filter { index in
            let observation = observations[index]
            return observation.providerID == "codex" && observation.quotaID == "codex-session"
        }
        let indicesByAccount = Dictionary(grouping: legacyIndices) { index in
            observations[index].accountScopeID
        }
        var weeklyIndices: Set<Int> = []

        for indices in indicesByAccount.values {
            let sorted = indices.sorted {
                observations[$0].resetAt < observations[$1].resetAt
            }
            var cluster: [Int] = []
            var previousResetAt: Date?

            func finishCluster() {
                guard cluster.contains(where: { index in
                    observations[index].resetAt.timeIntervalSince(observations[index].capturedAt)
                        > longWindowLeadThreshold
                }) else {
                    return
                }
                weeklyIndices.formUnion(cluster)
            }

            for index in sorted {
                let resetAt = observations[index].resetAt
                if let previousResetAt,
                   resetAt.timeIntervalSince(previousResetAt) > resetClusterTolerance {
                    finishCluster()
                    cluster.removeAll(keepingCapacity: true)
                }
                cluster.append(index)
                previousResetAt = resetAt
            }
            finishCluster()
        }

        return observations.enumerated().map { index, observation in
            guard weeklyIndices.contains(index) else {
                return observation
            }
            return QuotaObservation(
                providerID: observation.providerID,
                accountScopeID: observation.accountScopeID,
                quotaID: "codex-weekly",
                remainingFraction: observation.remainingFraction,
                capturedAt: observation.capturedAt,
                resetAt: observation.resetAt
            )
        }
    }
}

public enum WeeklySubscriptionReviewAnalyzer {
    public static let weeklyQuotaID = "codex-weekly"
    public static let nominalWeeklyDuration: TimeInterval = 7 * 24 * 60 * 60
    public static let expectedSampleInterval: TimeInterval = 5 * 60
    public static let maximumCycleStartOffset: TimeInterval = 12 * 60 * 60
    public static let maximumCycleEndLead: TimeInterval = 6 * 60 * 60
    public static let minimumSampleCoverageFraction = 0.15
    public static let maximumRhythmGap: TimeInterval = 4 * 60 * 60
    public static let minimumRhythmAttributionFraction = 0.5
    public static let minimumMeaningfulCycleUse = 0.02
    public static let meaningfulDayUseThreshold = 0.005
    public static let lowHeadroomThreshold = 0.05
    public static let ampleHeadroomThreshold = 0.35

    private static let minimumStartRemainingFraction = 0.98
    private static let capacityIncreaseThreshold = 0.02
    private static let resetBoundaryTolerance: TimeInterval = 5 * 60
    private static let minimumBaselineCycleCount = 3
    private static let minimumPlanFitCycleCount = 3
    private static let maximumBaselineCycleCount = 4
    private static let maximumPlanFitCycleCount = 4

    public static func analyze(
        current: [QuotaObservation],
        history: [QuotaObservation],
        now: Date,
        calendar: Calendar = .current
    ) -> WeeklySubscriptionReview? {
        let normalizedCurrent = CodexQuotaObservationNormalizer.normalize(current)
        guard let currentWeekly = normalizedCurrent
            .filter({ $0.quotaID == weeklyQuotaID && $0.resetAt > now })
            .max(by: { $0.capturedAt < $1.capturedAt })
        else {
            return nil
        }

        let normalizedHistory = CodexQuotaObservationNormalizer.normalize(history)
        let points = deduplicated(
            (normalizedHistory + normalizedCurrent)
                .filter { observation in
                    observation.providerID == currentWeekly.providerID
                        && observation.accountScopeID == currentWeekly.accountScopeID
                        && observation.quotaID == weeklyQuotaID
                        && observation.capturedAt <= now
                }
        )
        let cycles = cycleSegments(from: points)
        guard cycles.isEmpty == false else {
            return nil
        }

        // A capacity correction can split observations before the advertised reset.
        // Only a segment whose own reset has actually passed is a completed cycle.
        let completedCycles = cycles.dropLast().filter { cycle in
            guard let resetAt = cycle.last?.resetAt else {
                return false
            }
            return resetAt <= now.addingTimeInterval(resetBoundaryTolerance)
        }
        guard let latestCompletedPoints = completedCycles.last else {
            return .unavailable(
                providerID: currentWeekly.providerID,
                reason: .noCompletedCycle,
                generatedAt: now,
                currentResetAt: currentWeekly.resetAt
            )
        }
        guard let latestCompleted = completedCycleSummary(
            for: latestCompletedPoints,
            calendar: calendar
        ) else {
            return .unavailable(
                providerID: currentWeekly.providerID,
                reason: .insufficientCompletedCycleCoverage,
                generatedAt: now,
                currentResetAt: currentWeekly.resetAt
            )
        }

        let previousCompleted = completedCycles.dropLast().compactMap { cycle in
            completedCycleSummary(for: cycle, calendar: calendar)
        }
        let eligibleCompletedCycles = previousCompleted + [latestCompleted]

        return WeeklySubscriptionReview(
            providerID: currentWeekly.providerID,
            currentResetAt: currentWeekly.resetAt,
            completedCycle: latestCompleted,
            baselineComparison: baselineComparison(
                completedCycle: latestCompleted,
                previousCycles: previousCompleted
            ),
            planFit: planFit(for: eligibleCompletedCycles),
            eligibleCompletedCycleCount: eligibleCompletedCycles.count,
            generatedAt: now
        )
    }

    private static func cycleSegments(
        from points: [QuotaObservation]
    ) -> [[QuotaObservation]] {
        var cycles: [[QuotaObservation]] = []

        for point in points {
            guard let previous = cycles.last?.last else {
                cycles.append([point])
                continue
            }

            if startsNewCycle(point, after: previous) {
                cycles.append([point])
            } else {
                cycles[cycles.count - 1].append(point)
            }
        }

        return cycles
    }

    private static func startsNewCycle(
        _ point: QuotaObservation,
        after previous: QuotaObservation
    ) -> Bool {
        if point.remainingFraction > previous.remainingFraction + capacityIncreaseThreshold {
            return true
        }

        let passedPreviousReset = point.capturedAt
            >= previous.resetAt.addingTimeInterval(-resetBoundaryTolerance)
        let resetMovedForward = point.resetAt
            > previous.resetAt.addingTimeInterval(resetBoundaryTolerance)
        if passedPreviousReset && resetMovedForward {
            return true
        }

        return point.capturedAt.timeIntervalSince(previous.capturedAt)
            > nominalWeeklyDuration + resetBoundaryTolerance
    }

    private static func completedCycleSummary(
        for points: [QuotaObservation],
        calendar: Calendar
    ) -> WeeklySubscriptionCompletedCycleSummary? {
        guard let first = points.first,
              let last = points.last,
              points.count >= 2
        else {
            return nil
        }

        let resetAt = last.resetAt
        let startedAt = resetAt.addingTimeInterval(-nominalWeeklyDuration)
        let startOffset = first.capturedAt.timeIntervalSince(startedAt)
        let endLead = resetAt.timeIntervalSince(last.capturedAt)
        let expectedSamples = Int(floor(nominalWeeklyDuration / expectedSampleInterval)) + 1
        let sampleCoverage = min(1, Double(points.count) / Double(expectedSamples))

        guard first.remainingFraction >= minimumStartRemainingFraction,
              abs(startOffset) <= maximumCycleStartOffset,
              endLead >= 0,
              endLead <= maximumCycleEndLead,
              sampleCoverage >= minimumSampleCoverageFraction
        else {
            return nil
        }

        let lowestRemaining = points.reduce(first.remainingFraction) { remaining, point in
            min(remaining, point.remainingFraction)
        }
        let observedUsed = max(0, first.remainingFraction - lowestRemaining)

        return WeeklySubscriptionCompletedCycleSummary(
            quotaID: weeklyQuotaID,
            startedAt: startedAt,
            resetAt: resetAt,
            endingRemainingFraction: last.remainingFraction,
            lowestRemainingFraction: lowestRemaining,
            observedUsedFraction: observedUsed,
            sampleCount: points.count,
            sampleCoverageFraction: sampleCoverage,
            endObservationLead: endLead,
            rhythm: rhythmSummary(
                for: points,
                totalObservedUse: observedUsed,
                calendar: calendar
            )
        )
    }

    private static func rhythmSummary(
        for points: [QuotaObservation],
        totalObservedUse: Double,
        calendar: Calendar
    ) -> WeeklySubscriptionRhythmSummary? {
        if totalObservedUse < minimumMeaningfulCycleUse {
            return WeeklySubscriptionRhythmSummary(
                pattern: .quiet,
                activeDayCount: 0,
                peakWeekday: nil,
                topTwoDayUseFraction: 0,
                attributedUseFraction: 1
            )
        }

        guard let first = points.first else {
            return nil
        }
        var previousPoint = first
        var previousRemaining = first.remainingFraction
        var useByDay: [Date: Double] = [:]
        var attributedUse = 0.0

        for point in points.dropFirst() {
            let normalizedRemaining = min(previousRemaining, point.remainingFraction)
            let observedDrop = max(0, previousRemaining - normalizedRemaining)
            let interval = point.capturedAt.timeIntervalSince(previousPoint.capturedAt)

            if observedDrop > 0, interval > 0, interval <= maximumRhythmGap {
                let midpoint = previousPoint.capturedAt.addingTimeInterval(interval / 2)
                let day = calendar.startOfDay(for: midpoint)
                useByDay[day, default: 0] += observedDrop
                attributedUse += observedDrop
            }

            previousPoint = point
            previousRemaining = normalizedRemaining
        }

        let attributedFraction = min(1, attributedUse / totalObservedUse)
        guard attributedFraction >= minimumRhythmAttributionFraction else {
            return nil
        }

        let meaningfulDays = useByDay.filter { $0.value >= meaningfulDayUseThreshold }
        guard let peakDay = meaningfulDays.max(by: { $0.value < $1.value })?.key else {
            return nil
        }

        let rankedDayUse = useByDay.values.sorted(by: >)
        let topTwoUse = rankedDayUse.prefix(2).reduce(0, +)
        let topTwoFraction = attributedUse > 0 ? min(1, topTwoUse / attributedUse) : 0
        let activeDayCount = meaningfulDays.count

        let pattern: WeeklySubscriptionRhythmPattern
        if activeDayCount <= 2 || topTwoFraction >= 0.7 {
            pattern = .concentrated
        } else if activeDayCount >= 5 && topTwoFraction <= 0.5 {
            pattern = .steady
        } else {
            pattern = .mixed
        }

        return WeeklySubscriptionRhythmSummary(
            pattern: pattern,
            activeDayCount: activeDayCount,
            peakWeekday: calendar.component(.weekday, from: peakDay),
            topTwoDayUseFraction: topTwoFraction,
            attributedUseFraction: attributedFraction
        )
    }

    private static func baselineComparison(
        completedCycle: WeeklySubscriptionCompletedCycleSummary,
        previousCycles: [WeeklySubscriptionCompletedCycleSummary]
    ) -> WeeklySubscriptionBaselineComparison? {
        let comparisonCycles = Array(previousCycles.suffix(maximumBaselineCycleCount))
        guard comparisonCycles.count >= minimumBaselineCycleCount else {
            return nil
        }

        let medianUsed = median(comparisonCycles.map(\.observedUsedFraction))
        return WeeklySubscriptionBaselineComparison(
            usedDifferenceFraction: completedCycle.observedUsedFraction - medianUsed,
            medianUsedFraction: medianUsed,
            comparisonCycleCount: comparisonCycles.count
        )
    }

    private static func planFit(
        for completedCycles: [WeeklySubscriptionCompletedCycleSummary]
    ) -> WeeklySubscriptionPlanFitSummary? {
        let evaluated = Array(completedCycles.suffix(maximumPlanFitCycleCount))
        guard evaluated.count >= minimumPlanFitCycleCount else {
            return nil
        }

        let ampleCount = evaluated.filter {
            $0.endingRemainingFraction >= ampleHeadroomThreshold
        }.count
        let nearLimitCount = evaluated.filter {
            $0.lowestRemainingFraction <= lowHeadroomThreshold
        }.count

        let pattern: WeeklySubscriptionPlanFitPattern
        if ampleCount >= 3 {
            pattern = .ampleHeadroom
        } else if nearLimitCount >= 2 {
            pattern = .frequentPressure
        } else {
            pattern = .mixed
        }

        return WeeklySubscriptionPlanFitSummary(
            pattern: pattern,
            evaluatedCycleCount: evaluated.count,
            ampleHeadroomCycleCount: ampleCount,
            nearLimitCycleCount: nearLimitCount
        )
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func deduplicated(
        _ points: [QuotaObservation]
    ) -> [QuotaObservation] {
        var pointsByDate: [Date: QuotaObservation] = [:]
        for point in points {
            pointsByDate[point.capturedAt] = point
        }
        return pointsByDate.values.sorted { $0.capturedAt < $1.capturedAt }
    }
}
