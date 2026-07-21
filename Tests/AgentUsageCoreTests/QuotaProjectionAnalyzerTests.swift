import AgentUsageCore
import Foundation
import Testing

@Test func quotaProjectionWaitsForEnoughContinuousHistory() throws {
    let now = projectionDate()
    let resetAt = now.addingTimeInterval(2 * 3_600)
    let series = projectionSeries(
        remaining: [0.84, 0.82, 0.8, 0.78],
        interval: 10 * 60,
        now: now,
        resetAt: resetAt
    )

    let projection = try #require(analyze(series: series, now: now))

    #expect(projection.confidence == .unavailable)
    #expect(projection.availabilityReason == .insufficientHistory)
}

@Test func quotaProjectionReturnsAnErrorRangeAtReset() throws {
    let now = projectionDate()
    let resetAt = now.addingTimeInterval(2 * 3_600)
    let series = projectionSeries(
        remaining: [0.8, 0.775, 0.75, 0.725, 0.7],
        interval: 15 * 60,
        now: now,
        resetAt: resetAt
    )

    let projection = try #require(analyze(series: series, now: now))
    let window = try #require(projection.constrainingWindow)

    #expect(projection.confidence == .estimated)
    #expect(abs((window.consumptionPerHour ?? 0) - 0.1) < 0.000_001)
    #expect(abs((window.projectedRemainingAtReset ?? 0) - 0.5) < 0.000_001)
    #expect((window.projectedRemainingLowerBound ?? 1) < 0.5)
    #expect((window.projectedRemainingUpperBound ?? 0) > 0.5)
    #expect(window.outcome == .remainingAtReset)
}

@Test func quotaProjectionHandlesAnIdleWindowWithoutInventingBurn() throws {
    let now = projectionDate()
    let resetAt = now.addingTimeInterval(4 * 3_600)
    let series = projectionSeries(
        remaining: Array(repeating: 0.9, count: 7),
        interval: 10 * 60,
        now: now,
        resetAt: resetAt
    )

    let projection = try #require(analyze(series: series, now: now))
    let window = try #require(projection.constrainingWindow)

    #expect(window.consumptionPerHour == 0)
    #expect(window.projectedRemainingAtReset == 0.9)
    #expect(window.projectedExhaustionAt == nil)
    #expect(window.outcome == .remainingAtReset)
}

@Test func quotaProjectionRemovesAOneSampleSourceSpike() throws {
    let now = projectionDate()
    let resetAt = now.addingTimeInterval(2 * 3_600)
    let series = projectionSeries(
        remaining: [0.9, 0.88, 0.86, 0.5, 0.85, 0.83, 0.81],
        interval: 10 * 60,
        now: now,
        resetAt: resetAt
    )

    let projection = try #require(analyze(series: series, now: now))
    let window = try #require(projection.constrainingWindow)

    #expect(projection.confidence == .estimated)
    #expect((window.projectedRemainingAtReset ?? 0) > 0.55)
    #expect(window.sampleCount == 6)
}

@Test func quotaProjectionStartsANewTrendAfterSustainedCapacityIncrease() throws {
    let now = projectionDate()
    let resetAt = now.addingTimeInterval(2 * 3_600)
    let series = projectionSeries(
        remaining: [0.3, 0.9, 0.88, 0.86, 0.84, 0.82],
        interval: 15 * 60,
        now: now,
        resetAt: resetAt
    )

    let projection = try #require(analyze(series: series, now: now))
    let window = try #require(projection.constrainingWindow)

    #expect(projection.confidence == .estimated)
    #expect(window.sampleCount == 5)
    #expect(window.coverageDuration == 60 * 60)
}

@Test func quotaProjectionRejectsSparseLongWindowHistory() throws {
    let now = projectionDate()
    let resetAt = now.addingTimeInterval(48 * 3_600)
    let series = projectionSeries(
        remaining: [0.9, 0.88, 0.86, 0.84, 0.82],
        interval: 90 * 60,
        now: now,
        resetAt: resetAt
    )

    let projection = try #require(analyze(series: series, now: now))

    #expect(projection.confidence == .unavailable)
    #expect(projection.availabilityReason == .sparseHistory)
}

@Test func quotaProjectionKeepsLongTrendAcrossAnOvernightSamplingGap() throws {
    let now = projectionDate()
    let resetAt = now.addingTimeInterval(5 * 3_600)
    let olderPoints = (0...28).map { index in
        projectionObservation(
            remaining: 0.9 - (Double(index) * (0.03 / 28)),
            capturedAt: now.addingTimeInterval((-20 * 3_600) + Double(index * 15 * 60)),
            resetAt: resetAt
        )
    }
    let recentPoints = (0...16).map { index in
        projectionObservation(
            remaining: 0.87,
            capturedAt: now.addingTimeInterval((-4 * 3_600) + Double(index * 15 * 60)),
            resetAt: resetAt
        )
    }
    let series = olderPoints + recentPoints

    let projection = try #require(analyze(series: series, now: now))
    let window = try #require(projection.constrainingWindow)

    #expect(projection.confidence == .estimated)
    #expect(window.sampleCount == 46)
    #expect(window.coverageDuration == 20 * 3_600)
}

@Test func quotaProjectionDoesNotTreatACrossGapDropAsRecentPace() throws {
    let now = projectionDate()
    let resetAt = now.addingTimeInterval(5 * 3_600)
    let olderPoints = (0...96).map { index in
        projectionObservation(
            remaining: 0.9,
            capturedAt: now.addingTimeInterval((-30 * 3_600) + Double(index * 15 * 60)),
            resetAt: resetAt
        )
    }
    let recentPoints = (0...6).map { index in
        projectionObservation(
            remaining: 0.8,
            capturedAt: now.addingTimeInterval((-60 * 60) + Double(index * 10 * 60)),
            resetAt: resetAt
        )
    }
    let series = olderPoints + recentPoints

    let projection = try #require(analyze(series: series, now: now))
    let window = try #require(projection.constrainingWindow)

    #expect(projection.confidence == .estimated)
    #expect(abs((window.consumptionPerHour ?? 0) - (0.1 / 30)) < 0.000_001)
}

@Test func quotaProjectionStillRejectsADiscontinuousShortWindow() throws {
    let now = projectionDate()
    let resetAt = now.addingTimeInterval(2 * 3_600)
    let minutesBeforeNow = [60, 55, 50, 4, 0]
    let series = minutesBeforeNow.enumerated().map { index, minutes in
        projectionObservation(
            remaining: 0.9 - (Double(index) * 0.01),
            capturedAt: now.addingTimeInterval(-Double(minutes * 60)),
            resetAt: resetAt
        )
    }

    let projection = try #require(analyze(series: series, now: now))

    #expect(projection.confidence == .unavailable)
    #expect(projection.availabilityReason == .sparseHistory)
}

@Test func quotaProjectionWeightsARecentUsageChangeMoreHeavily() throws {
    let now = projectionDate()
    let resetAt = now.addingTimeInterval(60 * 60)
    let remaining = [
        0.95, 0.945, 0.94, 0.935, 0.93, 0.925, 0.92,
        0.915, 0.91, 0.905, 0.9, 0.895, 0.89,
        0.875, 0.86, 0.845, 0.83, 0.815, 0.8
    ]
    let series = projectionSeries(
        remaining: remaining,
        interval: 10 * 60,
        now: now,
        resetAt: resetAt
    )

    let projection = try #require(analyze(series: series, now: now))
    let window = try #require(projection.constrainingWindow)

    #expect((window.consumptionPerHour ?? 0) > 0.055)
    #expect((window.projectedRemainingAtReset ?? 1) < 0.745)
}

@Test func quotaProjectionSuppressesAHighlyUnstableTrend() throws {
    let now = projectionDate()
    let resetAt = now.addingTimeInterval(2 * 3_600)
    let series = projectionSeries(
        remaining: [0.95, 0.94, 0.93, 0.92, 0.91, 0.9, 0.89, 0.88, 0.4, 0.39, 0.38, 0.37],
        interval: 10 * 60,
        now: now,
        resetAt: resetAt
    )

    let projection = try #require(analyze(series: series, now: now))

    #expect(projection.confidence == .unavailable)
    #expect(projection.availabilityReason == .unstableTrend)
}

@Test func quotaProjectionGivesBurstyUsageAWiderRange() throws {
    let now = projectionDate()
    let resetAt = now.addingTimeInterval(60 * 60)
    let smooth = projectionSeries(
        remaining: [0.9, 0.89, 0.88, 0.87, 0.86, 0.85, 0.84, 0.83, 0.82, 0.81, 0.8, 0.79, 0.78],
        interval: 10 * 60,
        now: now,
        resetAt: resetAt
    )
    let bursty = projectionSeries(
        remaining: [0.9, 0.9, 0.9, 0.86, 0.86, 0.86, 0.82, 0.82, 0.82, 0.78, 0.78, 0.78, 0.78],
        interval: 10 * 60,
        now: now,
        resetAt: resetAt
    )

    let smoothProjection = try #require(analyze(series: smooth, now: now))
    let burstyProjection = try #require(analyze(series: bursty, now: now))
    let smoothWindow = try #require(smoothProjection.constrainingWindow)
    let burstyWindow = try #require(burstyProjection.constrainingWindow)

    #expect(smoothProjection.confidence == .estimated)
    #expect(burstyProjection.confidence == .estimated)
    #expect((burstyWindow.forecastErrorFraction ?? 0) > (smoothWindow.forecastErrorFraction ?? 1))
}

@Test func quotaProjectionKeepsAWideLongForecastWhenExhaustionIsStillCertain() throws {
    let now = projectionDate()
    let resetAt = now.addingTimeInterval(94 * 3_600)
    var remaining = 0.9
    let burstIndexes = Set([28, 56, 84, 112, 140])
    let series = (0...144).map { index in
        if burstIndexes.contains(index) {
            remaining -= 0.1
        }
        return projectionObservation(
            remaining: remaining,
            capturedAt: now.addingTimeInterval((-36 * 3_600) + Double(index * 15 * 60)),
            resetAt: resetAt
        )
    }

    let projection = try #require(analyze(series: series, now: now))
    let window = try #require(projection.constrainingWindow)

    #expect(
        (window.forecastErrorFraction ?? 0)
            > QuotaWindowProjection.maximumPreciseForecastError
    )
    #expect(window.projectedRemainingUpperBound.map { $0 <= 0 } == true)
    #expect(window.outcome == .likelyExhaustsBeforeReset)
    #expect(projection.confidence == .estimated)
}

@Test func quotaProjectionUsesTheMostConstrainedEstimatedWindow() throws {
    let now = projectionDate()
    let resetAt = now.addingTimeInterval(2 * 3_600)
    let session = projectionSeries(
        quotaID: "codex-session",
        remaining: [0.9, 0.8875, 0.875, 0.8625, 0.85],
        interval: 15 * 60,
        now: now,
        resetAt: resetAt
    )
    let weekly = projectionSeries(
        quotaID: "codex-weekly",
        remaining: [0.4, 0.35, 0.3, 0.25, 0.2],
        interval: 15 * 60,
        now: now,
        resetAt: resetAt
    )
    let current = [session.last, weekly.last].compactMap { $0 }
    let history = Array(session.dropLast()) + Array(weekly.dropLast())

    let projection = try #require(
        QuotaProjectionAnalyzer.analyze(current: current, history: history, now: now)
    )

    #expect(projection.constrainingQuotaID == "codex-weekly")
    #expect(projection.constrainingWindow?.outcome == .likelyExhaustsBeforeReset)
}

@Test func quotaProjectionDoesNotMixAccountsOrResetCycles() throws {
    let now = projectionDate()
    let resetAt = now.addingTimeInterval(4 * 3_600)
    let current = projectionObservation(
        remaining: 0.5,
        capturedAt: now,
        resetAt: resetAt
    )
    let history = [
        projectionObservation(
            remaining: 0.9,
            capturedAt: now.addingTimeInterval(-60 * 60),
            resetAt: resetAt,
            accountScopeID: "other-account"
        ),
        projectionObservation(
            remaining: 0.8,
            capturedAt: now.addingTimeInterval(-30 * 60),
            resetAt: resetAt.addingTimeInterval(3_600)
        )
    ]

    let projection = try #require(
        QuotaProjectionAnalyzer.analyze(current: [current], history: history, now: now)
    )

    #expect(projection.confidence == .unavailable)
    #expect(projection.windows.first?.sampleCount == 1)
}

@Test func quotaProjectionRequiresACurrentUnexpiredOfficialPoint() {
    let now = projectionDate()
    let expired = projectionObservation(
        remaining: 0.5,
        capturedAt: now.addingTimeInterval(-60),
        resetAt: now
    )

    #expect(QuotaProjectionAnalyzer.analyze(current: [expired], history: [], now: now) == nil)
}

private func analyze(
    series: [QuotaObservation],
    now: Date
) -> QuotaProjection? {
    guard let current = series.last else {
        return nil
    }
    return QuotaProjectionAnalyzer.analyze(
        current: [current],
        history: Array(series.dropLast()),
        now: now
    )
}

private func projectionSeries(
    quotaID: String = "codex-session",
    remaining: [Double],
    interval: TimeInterval,
    now: Date,
    resetAt: Date
) -> [QuotaObservation] {
    remaining.enumerated().map { index, value in
        let intervalsBeforeNow = remaining.count - index - 1
        return projectionObservation(
            quotaID: quotaID,
            remaining: value,
            capturedAt: now.addingTimeInterval(-Double(intervalsBeforeNow) * interval),
            resetAt: resetAt
        )
    }
}

private func projectionDate() -> Date {
    Date(timeIntervalSince1970: 1_750_000_000)
}

private func projectionObservation(
    quotaID: String = "codex-session",
    remaining: Double,
    capturedAt: Date,
    resetAt: Date,
    accountScopeID: String = "account-scope"
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
