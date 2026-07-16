import AgentUsageCore
import Foundation
import Testing

@Test func usageBarDecodesLegacyUsedFractionAsRemainingFraction() throws {
    let json = """
    {
      "id": "codex-session",
      "label": "Session",
      "usedFraction": 0.42,
      "usedText": "42% left",
      "resetText": "Resets in 2h",
      "confidence": "Official"
    }
    """

    let bar = try JSONDecoder().decode(UsageBar.self, from: Data(json.utf8))

    #expect(bar.remainingFraction == 0.42)
}

@Test func usageBarEncodesOnlyRemainingFraction() throws {
    let resetAt = Date(timeIntervalSince1970: 1_704_070_800)
    let bar = UsageBar(
        id: "codex-session",
        label: "Session",
        remainingFraction: 0.95,
        usedText: "95% left",
        resetText: "Resets in 2h",
        resetAt: resetAt,
        confidence: .official
    )

    let data = try JSONEncoder().encode(bar)
    let text = String(decoding: data, as: UTF8.self)
    let decoded = try JSONDecoder().decode(UsageBar.self, from: data)

    #expect(text.contains("remainingFraction"))
    #expect(text.contains("usedFraction") == false)
    #expect(text.contains("resetAt"))
    #expect(decoded.resetAt == resetAt)
    #expect(decoded.displayResetText(now: Date(timeIntervalSince1970: 1_704_067_200)) == "Resets in 1h 0m")
}

@Test func usageMetricSupportsOptionalSubvalueForCompactCostText() throws {
    let metric = UsageMetric(
        id: "today-tokens",
        label: "Today tokens",
        value: "2.0M",
        subvalue: "≈ $34.10",
        detail: "Observed from local Codex session logs",
        confidence: .observed
    )

    let data = try JSONEncoder().encode(metric)
    let decoded = try JSONDecoder().decode(UsageMetric.self, from: data)

    #expect(decoded.subvalue == "≈ $34.10")

    let legacy = Data(#"{"id":"m","label":"Metric","value":"1","detail":"","confidence":"Observed"}"#.utf8)
    let legacyDecoded = try JSONDecoder().decode(UsageMetric.self, from: legacy)

    #expect(legacyDecoded.subvalue == nil)
}

@Test func dateTimestampNormalizesSecondsAndMilliseconds() {
    let seconds = Date(timestamp: 1_704_067_200)
    let milliseconds = Date(timestamp: 1_704_067_200_000)

    #expect(seconds == Date(timeIntervalSince1970: 1_704_067_200))
    #expect(milliseconds == seconds)
}

@Test func providerSnapshotDecodesLegacyPayloadWithoutAccounts() throws {
    let json = #"{"id":"deepseek","name":"DeepSeek","kind":"api","updatedAt":0,"health":"Ready","headline":"Ready","metrics":[],"bars":[],"notes":[],"actions":[]}"#
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .secondsSince1970

    let snapshot = try decoder.decode(ProviderSnapshot.self, from: Data(json.utf8))

    #expect(snapshot.accounts == nil)
    #expect(snapshot.sourceDiagnostics == nil)
}

@Test func providerSourceDiagnosticRoundTripsAndPreservesHistory() throws {
    let previousSuccessAt = Date(timeIntervalSince1970: 1_700_000_000)
    let failedAt = Date(timeIntervalSince1970: 1_700_000_100)
    let previous = ProviderSourceDiagnostic(
        id: "official-api",
        name: "Official API",
        confidence: .official,
        status: .success,
        attemptedAt: previousSuccessAt,
        lastSuccessAt: previousSuccessAt,
        message: "Current quota returned."
    )
    let latest = ProviderSourceDiagnostic(
        id: "official-api",
        name: "Official API",
        confidence: .official,
        status: .failure,
        attemptedAt: failedAt,
        lastFailureAt: failedAt,
        message: "Request failed."
    )

    let diagnostic = latest.preservingHistory(from: previous).markingFallback()
    let data = try JSONEncoder().encode(diagnostic)
    let decoded = try JSONDecoder().decode(ProviderSourceDiagnostic.self, from: data)

    #expect(decoded == diagnostic)
    #expect(decoded.lastSuccessAt == previousSuccessAt)
    #expect(decoded.lastFailureAt == failedAt)
    #expect(decoded.isFallback)
}

@Test func providerAccountAndModelSummaryRoundTrip() throws {
    let account = ProviderAccountSnapshot(
        id: "key-1",
        name: "Production",
        detail: "Official API key",
        isDefault: true,
        health: .ready,
        metrics: [
            UsageMetric(
                id: "today-tokens",
                label: "Today tokens",
                value: "300",
                confidence: .observed
            )
        ],
        activity: [
            UsageActivityBucket(
                id: "day-2026-07-13",
                label: "Jul 13",
                axisLabel: "13",
                value: 300,
                valueText: "300",
                confidence: .official
            )
        ],
        activityTitle: "Last 30 completed UTC days",
        models: [
            UsageModelSummary(
                id: "deepseek-chat",
                model: "deepseek-chat",
                requestCount: 2,
                inputTokens: 100,
                outputTokens: 200,
                totalTokens: 300,
                latestAt: Date(timeIntervalSince1970: 1_700_000_000),
                confidence: .observed
            )
        ]
    )
    let snapshot = ProviderSnapshot(
        id: "deepseek",
        name: "DeepSeek",
        kind: .api,
        health: .ready,
        headline: "Ready",
        metrics: [],
        bars: [],
        accounts: [account],
        notes: [],
        actions: []
    )

    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(ProviderSnapshot.self, from: data)

    #expect(decoded == snapshot)
    #expect(decoded.accounts?.first?.models.first?.spendUSD == nil)
}

@Test func activityBucketDecodesLegacyPayloadWithoutAxisLabel() throws {
    let legacy = Data(#"{"id":"hour-9","label":"09:00","value":42,"valueText":"42","confidence":"Observed"}"#.utf8)

    let bucket = try JSONDecoder().decode(UsageActivityBucket.self, from: legacy)

    #expect(bucket.axisLabel == nil)
}
