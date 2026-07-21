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
    public static let minimumCoverageDuration: TimeInterval = 30 * 60
    public static let maximumComparisonProgressDifference: TimeInterval = 2 * 60 * 60

    private static let cycleStartLeadThreshold: TimeInterval = 6 * 24 * 60 * 60
    private static let capacityIncreaseThreshold = 0.02
    private static let resetBoundaryTolerance: TimeInterval = 5 * 60

    public static func analyze(
        current: [QuotaObservation],
        history: [QuotaObservation],
        now: Date
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
        guard let currentCycle = cycles.last,
              let currentSummary = summary(for: currentCycle)
        else {
            return .unavailable(
                providerID: currentWeekly.providerID,
                reason: .insufficientCurrentCycle,
                generatedAt: now
            )
        }

        let previousCycle = cycles.dropLast().last
        let comparisonResult = comparison(
            currentCycle: currentCycle,
            currentSummary: currentSummary,
            previousCycle: previousCycle
        )

        return WeeklySubscriptionReview(
            providerID: currentWeekly.providerID,
            currentCycle: currentSummary,
            comparison: comparisonResult.comparison,
            comparisonAvailabilityReason: comparisonResult.reason,
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

    private static func summary(
        for points: [QuotaObservation]
    ) -> WeeklySubscriptionCycleSummary? {
        guard let first = points.first,
              let last = points.last,
              points.count >= 2
        else {
            return nil
        }

        let coverageDuration = last.capturedAt.timeIntervalSince(first.capturedAt)
        guard coverageDuration >= minimumCoverageDuration else {
            return nil
        }

        let maximumResetLead = points.map { point in
            point.resetAt.timeIntervalSince(point.capturedAt)
        }.max() ?? 0
        let startsNearCycleBeginning = first.remainingFraction >= 0.98
            && maximumResetLead >= cycleStartLeadThreshold
        let usageScope: WeeklySubscriptionUsageScope = startsNearCycleBeginning
            ? .cycleToDate
            : .observedSpan
        let expectedSamples = max(1, Int(floor(coverageDuration / expectedSampleInterval)) + 1)
        let sampleCoverage = min(1, Double(points.count) / Double(expectedSamples))
        let normalizedRemaining = points.reduce(first.remainingFraction) { remaining, point in
            min(remaining, point.remainingFraction)
        }

        return WeeklySubscriptionCycleSummary(
            quotaID: weeklyQuotaID,
            resetAt: last.resetAt,
            currentRemainingFraction: last.remainingFraction,
            observedUsedFraction: max(0, first.remainingFraction - normalizedRemaining),
            sampleCount: points.count,
            coverageDuration: coverageDuration,
            cycleCoverageFraction: startsNearCycleBeginning
                ? min(1, coverageDuration / nominalWeeklyDuration)
                : nil,
            sampleCoverageFraction: sampleCoverage,
            usageScope: usageScope
        )
    }

    private static func comparison(
        currentCycle: [QuotaObservation],
        currentSummary: WeeklySubscriptionCycleSummary,
        previousCycle: [QuotaObservation]?
    ) -> (
        comparison: WeeklySubscriptionComparison?,
        reason: WeeklySubscriptionComparisonAvailabilityReason?
    ) {
        guard let previousCycle else {
            return (nil, .noPreviousCycle)
        }
        guard currentSummary.usageScope == .cycleToDate,
              let previousSummary = summary(for: previousCycle),
              previousSummary.usageScope == .cycleToDate,
              let currentFirst = currentCycle.first,
              let currentLast = currentCycle.last,
              let previousFirst = previousCycle.first
        else {
            return (nil, .insufficientPreviousCoverage)
        }

        let currentProgress = currentLast.capturedAt.timeIntervalSince(currentFirst.capturedAt)
        let targetDate = previousFirst.capturedAt.addingTimeInterval(currentProgress)
        guard let match = previousCycle.min(by: {
            abs($0.capturedAt.timeIntervalSince(targetDate))
                < abs($1.capturedAt.timeIntervalSince(targetDate))
        }) else {
            return (nil, .noComparablePoint)
        }

        let progressDifference = abs(match.capturedAt.timeIntervalSince(targetDate))
        guard progressDifference <= maximumComparisonProgressDifference else {
            return (nil, .noComparablePoint)
        }

        return (
            WeeklySubscriptionComparison(
                remainingDifferenceFraction: currentSummary.currentRemainingFraction
                    - match.remainingFraction,
                previousRemainingFraction: match.remainingFraction,
                matchedProgressDifference: progressDifference
            ),
            nil
        )
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
