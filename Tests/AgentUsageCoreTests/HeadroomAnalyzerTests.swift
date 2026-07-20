import AgentUsageCore
import Foundation
import Testing

@Test func headroomLearnsUntilShortWindowHasEnoughHistory() throws {
    let now = headroomDate()
    let resetAt = now.addingTimeInterval(4 * 3_600)
    let current = headroomObservation(remaining: 0.8, capturedAt: now, resetAt: resetAt)
    let history = [
        headroomObservation(remaining: 0.84, capturedAt: now.addingTimeInterval(-10 * 60), resetAt: resetAt),
        headroomObservation(remaining: 0.82, capturedAt: now.addingTimeInterval(-5 * 60), resetAt: resetAt)
    ]

    let insight = try #require(HeadroomAnalyzer.analyze(current: [current], history: history, now: now))
    let window = try #require(insight.windows.first)

    #expect(insight.weather == .learning)
    #expect(insight.confidence == .unavailable)
    #expect(window.weather == .learning)
    #expect(window.availabilityReason == .insufficientHistory)
}

@Test func headroomProjectsClearCapacityAtRecentPace() throws {
    let now = headroomDate()
    let resetAt = now.addingTimeInterval(2 * 3_600)
    let current = headroomObservation(remaining: 0.7, capturedAt: now, resetAt: resetAt)
    let history = [
        headroomObservation(remaining: 0.8, capturedAt: now.addingTimeInterval(-3_600), resetAt: resetAt),
        headroomObservation(remaining: 0.75, capturedAt: now.addingTimeInterval(-1_800), resetAt: resetAt)
    ]

    let insight = try #require(HeadroomAnalyzer.analyze(current: [current], history: history, now: now))
    let window = try #require(insight.windows.first)

    #expect(insight.weather == .clear)
    #expect(insight.confidence == .estimated)
    #expect(abs((window.consumptionPerHour ?? 0) - 0.1) < 0.000_001)
    #expect(abs((window.projectedRemainingAtReset ?? 0) - 0.5) < 0.000_001)
}

@Test func headroomMarksNarrowPositiveHeadroomAsWindy() throws {
    let now = headroomDate()
    let resetAt = now.addingTimeInterval(90 * 60)
    let current = headroomObservation(remaining: 0.25, capturedAt: now, resetAt: resetAt)
    let history = [
        headroomObservation(remaining: 0.35, capturedAt: now.addingTimeInterval(-3_600), resetAt: resetAt),
        headroomObservation(remaining: 0.3, capturedAt: now.addingTimeInterval(-1_800), resetAt: resetAt)
    ]

    let insight = try #require(HeadroomAnalyzer.analyze(current: [current], history: history, now: now))
    let window = try #require(insight.windows.first)

    #expect(insight.weather == .windy)
    #expect(abs((window.projectedRemainingAtReset ?? 0) - 0.1) < 0.000_001)
}

@Test func headroomMarksProjectedExhaustionBeforeResetAsStorm() throws {
    let now = headroomDate()
    let resetAt = now.addingTimeInterval(3 * 3_600)
    let current = headroomObservation(remaining: 0.2, capturedAt: now, resetAt: resetAt)
    let history = [
        headroomObservation(remaining: 0.3, capturedAt: now.addingTimeInterval(-3_600), resetAt: resetAt),
        headroomObservation(remaining: 0.25, capturedAt: now.addingTimeInterval(-1_800), resetAt: resetAt)
    ]

    let insight = try #require(HeadroomAnalyzer.analyze(current: [current], history: history, now: now))
    let window = try #require(insight.windows.first)
    let exhaustionAt = try #require(window.projectedExhaustionAt)

    #expect(insight.weather == .storm)
    #expect((window.projectedRemainingAtReset ?? 1) < 0)
    #expect(exhaustionAt < resetAt)
}

@Test func headroomUsesWorstEstimatedWindowAsCapacityWeather() throws {
    let now = headroomDate()
    let sessionReset = now.addingTimeInterval(2 * 3_600)
    let weeklyReset = now.addingTimeInterval(12 * 3_600)
    let current = [
        headroomObservation(
            quotaID: "codex-session",
            remaining: 0.8,
            capturedAt: now,
            resetAt: sessionReset
        ),
        headroomObservation(
            quotaID: "codex-weekly",
            remaining: 0.3,
            capturedAt: now,
            resetAt: weeklyReset
        )
    ]
    let history = [
        headroomObservation(
            quotaID: "codex-session",
            remaining: 0.85,
            capturedAt: now.addingTimeInterval(-3_600),
            resetAt: sessionReset
        ),
        headroomObservation(
            quotaID: "codex-session",
            remaining: 0.82,
            capturedAt: now.addingTimeInterval(-1_800),
            resetAt: sessionReset
        ),
        headroomObservation(
            quotaID: "codex-weekly",
            remaining: 0.7,
            capturedAt: now.addingTimeInterval(-12 * 3_600),
            resetAt: weeklyReset
        ),
        headroomObservation(
            quotaID: "codex-weekly",
            remaining: 0.5,
            capturedAt: now.addingTimeInterval(-6 * 3_600),
            resetAt: weeklyReset
        )
    ]

    let insight = try #require(HeadroomAnalyzer.analyze(current: current, history: history, now: now))

    #expect(insight.weather == .storm)
    #expect(insight.constrainingQuotaID == "codex-weekly")
    #expect(insight.windows.first { $0.quotaID == "codex-session" }?.weather == .clear)
}

@Test func headroomDoesNotMixAccountsOrResetCycles() throws {
    let now = headroomDate()
    let resetAt = now.addingTimeInterval(4 * 3_600)
    let current = headroomObservation(remaining: 0.5, capturedAt: now, resetAt: resetAt)
    let history = [
        headroomObservation(
            remaining: 0.9,
            capturedAt: now.addingTimeInterval(-3_600),
            resetAt: resetAt,
            accountScopeID: "other-account"
        ),
        headroomObservation(
            remaining: 0.8,
            capturedAt: now.addingTimeInterval(-1_800),
            resetAt: resetAt.addingTimeInterval(3_600)
        )
    ]

    let insight = try #require(HeadroomAnalyzer.analyze(current: [current], history: history, now: now))

    #expect(insight.weather == .learning)
    #expect(insight.windows.first?.sampleCount == 1)
}

@Test func headroomStartsANewTrendAfterMaterialCapacityIncrease() throws {
    let now = headroomDate()
    let resetAt = now.addingTimeInterval(12 * 3_600)
    let current = headroomObservation(remaining: 0.85, capturedAt: now, resetAt: resetAt)
    let history = [
        headroomObservation(remaining: 0.3, capturedAt: now.addingTimeInterval(-10 * 3_600), resetAt: resetAt),
        headroomObservation(remaining: 0.9, capturedAt: now.addingTimeInterval(-8 * 3_600), resetAt: resetAt),
        headroomObservation(remaining: 0.88, capturedAt: now.addingTimeInterval(-7 * 3_600), resetAt: resetAt)
    ]

    let insight = try #require(HeadroomAnalyzer.analyze(current: [current], history: history, now: now))
    let window = try #require(insight.windows.first)

    #expect(window.weather == .clear)
    #expect(window.sampleCount == 3)
    #expect(window.coverageDuration == 8 * 3_600)
    #expect(abs((window.consumptionPerHour ?? 0) - 0.00625) < 0.000_001)
}

@Test func headroomCanConfirmClearWeatherWithNoRecentConsumption() throws {
    let now = headroomDate()
    let resetAt = now.addingTimeInterval(4 * 3_600)
    let current = headroomObservation(remaining: 0.9, capturedAt: now, resetAt: resetAt)
    let history = [
        headroomObservation(remaining: 0.9, capturedAt: now.addingTimeInterval(-3_600), resetAt: resetAt),
        headroomObservation(remaining: 0.9, capturedAt: now.addingTimeInterval(-1_800), resetAt: resetAt)
    ]

    let insight = try #require(HeadroomAnalyzer.analyze(current: [current], history: history, now: now))
    let window = try #require(insight.windows.first)

    #expect(window.weather == .clear)
    #expect(window.consumptionPerHour == 0)
    #expect(window.projectedRemainingAtReset == 0.9)
    #expect(window.projectedExhaustionAt == nil)
    #expect(abs(window.sampleCoverageFraction - (3.0 / 13.0)) < 0.000_001)
}

@Test func headroomRequiresACurrentUnexpiredOfficialPoint() {
    let now = headroomDate()
    let expired = headroomObservation(
        remaining: 0.5,
        capturedAt: now.addingTimeInterval(-60),
        resetAt: now
    )

    #expect(HeadroomAnalyzer.analyze(current: [expired], history: [], now: now) == nil)
}

private func headroomDate() -> Date {
    Date(timeIntervalSince1970: 1_750_000_000)
}

private func headroomObservation(
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
