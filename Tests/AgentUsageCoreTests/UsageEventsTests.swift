import AgentUsageCore
import Foundation
import Testing

@Test func parsesDeepSeekUsageEventFromResponse() throws {
    let json = """
    {
      "id": "abc",
      "model": "deepseek-chat",
      "usage": {
        "prompt_tokens": 120,
        "completion_tokens": 80,
        "total_tokens": 200
      }
    }
    """

    let data = try #require(json.data(using: .utf8))
    let event = try #require(UsageEventParser.deepSeekEvent(from: data, accountID: "work-key"))

    #expect(event.providerID == "deepseek")
    #expect(event.accountID == "work-key")
    #expect(event.model == "deepseek-chat")
    #expect(event.inputTokens == 120)
    #expect(event.outputTokens == 80)
    #expect(event.totalTokens == 200)
}

@Test func parsesDeepSeekUsageEventFromStreamingSSE() throws {
    let sse = """
    data: {"id":"chunk-1","model":"deepseek-chat","choices":[{"delta":{"content":"hi"}}],"usage":null}

    data: {"id":"chunk-2","model":"deepseek-chat","choices":[],"usage":{"prompt_tokens":11,"completion_tokens":22,"total_tokens":33,"prompt_cache_hit_tokens":4,"prompt_cache_miss_tokens":7}}

    data: [DONE]

    """

    let data = try #require(sse.data(using: .utf8))
    let event = try #require(UsageEventParser.deepSeekEventFromSSE(from: data, accountID: "stream-key"))

    #expect(event.providerID == "deepseek")
    #expect(event.accountID == "stream-key")
    #expect(event.model == "deepseek-chat")
    #expect(event.inputTokens == 11)
    #expect(event.outputTokens == 22)
    #expect(event.totalTokens == 33)
    #expect(event.cachedInputTokens == 4)
    #expect(event.uncachedInputTokens == 7)
}

@Test func summarizesUsageEvents() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let calendar = Calendar(identifier: .gregorian)
    let events = [
        UsageEvent(providerID: "deepseek", model: "deepseek-chat", inputTokens: 10, outputTokens: 20, totalTokens: 30, createdAt: now, confidence: .observed),
        UsageEvent(providerID: "deepseek", model: "deepseek-reasoner", inputTokens: 100, outputTokens: 150, totalTokens: 250, createdAt: now, confidence: .observed)
    ]

    let summary = UsageSummarizer.summarize(events: events, now: now, calendar: calendar)

    #expect(summary.todayTokens == 280)
    #expect(summary.thirtyDayTokens == 280)
    #expect(summary.latestTokens == 30 || summary.latestTokens == 250)
    #expect(summary.topModel == "deepseek-reasoner")
}

@Test func summarizesThirtyDayTokensAsRollingWindow() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let calendar = Calendar(identifier: .gregorian)
    let events = [
        UsageEvent(providerID: "deepseek", model: "deepseek-chat", inputTokens: 10, outputTokens: 20, totalTokens: 30, createdAt: now.addingTimeInterval(-(30 * 24 * 3_600) + 1), confidence: .observed),
        UsageEvent(providerID: "deepseek", model: "deepseek-chat", inputTokens: 100, outputTokens: 200, totalTokens: 300, createdAt: now.addingTimeInterval(-(30 * 24 * 3_600) - 1), confidence: .observed)
    ]

    let summary = UsageSummarizer.summarize(events: events, now: now, calendar: calendar)

    #expect(summary.thirtyDayTokens == 30)
}

@Test func summarizesUsageWithoutCountingCachedInputAsUsedTokens() {
    let now = Date(timeIntervalSince1970: 1_704_067_200)
    let calendar = Calendar(identifier: .gregorian)
    let events = [
        UsageEvent(
            providerID: "codex",
            model: "gpt-5.5 high",
            inputTokens: 1_000,
            outputTokens: 100,
            totalTokens: 1_100,
            cachedInputTokens: 900,
            uncachedInputTokens: 100,
            createdAt: now,
            confidence: .observed
        )
    ]

    let summary = UsageSummarizer.summarize(
        events: events,
        now: now,
        calendar: calendar,
        accounting: .excludingCachedInput
    )

    #expect(summary.todayTokens == 200)
    #expect(summary.thirtyDayTokens == 200)
    #expect(summary.latestTokens == 200)
}

@Test func cachedInputExclusionFallsBackToReportedTotalAndBoundsMalformedValues() {
    let now = Date(timeIntervalSince1970: 1_704_067_200)
    let events = [
        UsageEvent(
            providerID: "codex",
            model: "gpt-5.5",
            inputTokens: 1_000,
            outputTokens: 100,
            totalTokens: 1_100,
            cachedInputTokens: nil,
            createdAt: now,
            confidence: .observed
        ),
        UsageEvent(
            providerID: "codex",
            model: "gpt-5.5",
            inputTokens: 1_000,
            outputTokens: 100,
            totalTokens: 1_100,
            cachedInputTokens: 2_000,
            createdAt: now,
            confidence: .observed
        )
    ]

    let summary = UsageSummarizer.summarize(
        events: events,
        now: now,
        calendar: Calendar(identifier: .gregorian),
        accounting: .excludingCachedInput
    )

    #expect(summary.todayTokens == 1_200)
}

@Test func excludedCachedInputDoesNotSelectAZeroWeightTopModel() {
    let now = Date(timeIntervalSince1970: 1_704_067_200)
    let event = UsageEvent(
        providerID: "codex",
        model: "gpt-5.5",
        inputTokens: 1_000,
        outputTokens: 0,
        totalTokens: 1_000,
        cachedInputTokens: 1_000,
        uncachedInputTokens: 0,
        createdAt: now,
        confidence: .observed
    )

    let summary = UsageSummarizer.summarize(
        events: [event],
        now: now,
        calendar: Calendar(identifier: .gregorian),
        accounting: .excludingCachedInput
    )

    #expect(summary.todayTokens == 0)
    #expect(summary.topModel == "No requests yet")
}

@Test func groupsUsageEventsIntoTodayHourlyBuckets() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = Date(timeIntervalSince1970: 1_704_067_200)
    let events = [
        UsageEvent(providerID: "deepseek", model: "deepseek-chat", inputTokens: 10, outputTokens: 20, totalTokens: 30, createdAt: start.addingTimeInterval(3_600 * 9 + 60), confidence: .observed),
        UsageEvent(providerID: "deepseek", model: "deepseek-chat", inputTokens: 10, outputTokens: 50, totalTokens: 60, createdAt: start.addingTimeInterval(3_600 * 9 + 600), confidence: .observed),
        UsageEvent(providerID: "deepseek", model: "deepseek-chat", inputTokens: 5, outputTokens: 15, totalTokens: 20, createdAt: start.addingTimeInterval(3_600 * 18), confidence: .observed)
    ]

    let buckets = UsageActivitySummarizer.todayHourlyBuckets(
        events: events,
        now: start.addingTimeInterval(3_600 * 20),
        calendar: calendar
    )

    #expect(buckets.count == 24)
    #expect(buckets[9].value == 90)
    #expect(buckets[18].value == 20)
    #expect(buckets[10].value == 0)
}

@Test func groupsActivityWithoutCountingCachedInputAsUsedTokens() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = Date(timeIntervalSince1970: 1_704_067_200)
    let event = UsageEvent(
        providerID: "codex",
        model: "gpt-5.5 high",
        inputTokens: 1_000,
        outputTokens: 100,
        totalTokens: 1_100,
        cachedInputTokens: 900,
        uncachedInputTokens: 100,
        createdAt: start.addingTimeInterval(3_600 * 9),
        confidence: .observed
    )

    let buckets = UsageActivitySummarizer.todayHourlyBuckets(
        events: [event],
        now: start.addingTimeInterval(3_600 * 12),
        calendar: calendar,
        accounting: .excludingCachedInput
    )

    #expect(buckets[9].value == 200)
    #expect(buckets[9].valueText == "200")
}

@Test func hourlyActivityUsesCompactTokenLabels() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = Date(timeIntervalSince1970: 1_704_067_200)
    let events = [
        UsageEvent(
            providerID: "codex",
            model: "gpt-5.6",
            inputTokens: 1_200,
            outputTokens: 0,
            totalTokens: 1_200,
            createdAt: start.addingTimeInterval(3_600),
            confidence: .observed
        ),
        UsageEvent(
            providerID: "codex",
            model: "gpt-5.6",
            inputTokens: 18_000_000,
            outputTokens: 0,
            totalTokens: 18_000_000,
            createdAt: start.addingTimeInterval(7_200),
            confidence: .observed
        ),
        UsageEvent(
            providerID: "codex",
            model: "gpt-5.6",
            inputTokens: 6_700_000_000,
            outputTokens: 0,
            totalTokens: 6_700_000_000,
            createdAt: start.addingTimeInterval(10_800),
            confidence: .observed
        )
    ]

    let buckets = UsageActivitySummarizer.todayHourlyBuckets(
        events: events,
        now: start.addingTimeInterval(14_400),
        calendar: calendar
    )

    #expect(buckets[1].valueText == "1.2K")
    #expect(buckets[2].valueText == "18.0M")
    #expect(buckets[3].valueText == "6.7B")
}

@Test func summarizesObservedEventsByModelWithinRollingWindow() {
    let now = Date(timeIntervalSince1970: 1_704_067_200)
    let recent = now.addingTimeInterval(-3_600)
    let old = now.addingTimeInterval(-(30 * 24 * 3_600) - 1)
    let events = [
        UsageEvent(
            providerID: "deepseek",
            accountID: "work",
            model: "deepseek-chat",
            inputTokens: 100,
            outputTokens: 40,
            totalTokens: 140,
            createdAt: recent,
            confidence: .observed
        ),
        UsageEvent(
            providerID: "deepseek",
            accountID: "work",
            model: "deepseek-chat",
            inputTokens: 10,
            outputTokens: 20,
            totalTokens: 30,
            createdAt: now,
            confidence: .observed
        ),
        UsageEvent(
            providerID: "deepseek",
            accountID: "work",
            model: "deepseek-reasoner",
            inputTokens: 1_000,
            outputTokens: 2_000,
            totalTokens: 3_000,
            createdAt: old,
            confidence: .observed
        )
    ]

    let summaries = UsageModelSummarizer.summarize(events: events, now: now)

    #expect(summaries.count == 1)
    #expect(summaries[0].model == "deepseek-chat")
    #expect(summaries[0].requestCount == 2)
    #expect(summaries[0].inputTokens == 110)
    #expect(summaries[0].outputTokens == 60)
    #expect(summaries[0].totalTokens == 170)
    #expect(summaries[0].spendUSD == nil)
    #expect(summaries[0].confidence == .observed)
    #expect(summaries[0].latestAt == now)
}

@Test func estimatesDeepSeekCostFromObservedTokenEvents() {
    let now = Date(timeIntervalSince1970: 1_704_067_200)
    let calendar = Calendar(identifier: .gregorian)
    let events = [
        UsageEvent(
            providerID: "deepseek",
            model: "deepseek-chat",
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            totalTokens: 2_000_000,
            cachedInputTokens: 0,
            uncachedInputTokens: 1_000_000,
            createdAt: now,
            confidence: .observed
        )
    ]

    let summary = DeepSeekCostEstimator.summarize(events: events, now: now, calendar: calendar)

    #expect(abs((summary.todayCost ?? 0) - 0.42) < 0.0001)
    #expect(abs((summary.thirtyDayCost ?? 0) - 0.42) < 0.0001)
    #expect(summary.todayUnpricedEventCount == 0)
    #expect(summary.thirtyDayUnpricedEventCount == 0)
}

@Test func estimatesDeepSeekCostWithRollingThirtyDayWindow() {
    let now = Date(timeIntervalSince1970: 1_704_067_200)
    let calendar = Calendar(identifier: .gregorian)
    let events = [
        UsageEvent(
            providerID: "deepseek",
            model: "deepseek-chat",
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            totalTokens: 2_000_000,
            cachedInputTokens: 0,
            uncachedInputTokens: 1_000_000,
            createdAt: now.addingTimeInterval(-(30 * 24 * 3_600) + 1),
            confidence: .observed
        ),
        UsageEvent(
            providerID: "deepseek",
            model: "deepseek-chat",
            inputTokens: 1_000_000,
            outputTokens: 1_000_000,
            totalTokens: 2_000_000,
            cachedInputTokens: 0,
            uncachedInputTokens: 1_000_000,
            createdAt: now.addingTimeInterval(-(30 * 24 * 3_600) - 1),
            confidence: .observed
        )
    ]

    let summary = DeepSeekCostEstimator.summarize(events: events, now: now, calendar: calendar)

    #expect(abs((summary.thirtyDayCost ?? 0) - 0.42) < 0.0001)
}

@Test func deepSeekCostEstimatorRejectsUnknownModelsInsteadOfGuessingFlashPricing() {
    let now = Date(timeIntervalSince1970: 1_704_067_200)
    let event = UsageEvent(
        providerID: "deepseek",
        model: "future-deepseek-model",
        inputTokens: 1_000,
        outputTokens: 500,
        totalTokens: 1_500,
        cachedInputTokens: 0,
        uncachedInputTokens: 1_000,
        createdAt: now,
        confidence: .observed
    )

    let summary = DeepSeekCostEstimator.summarize(events: [event], now: now)

    #expect(DeepSeekCostEstimator.cost(for: event) == nil)
    #expect(summary.todayCost == nil)
    #expect(summary.thirtyDayCost == nil)
    #expect(summary.todayUnpricedEventCount == 1)
}

@Test func deepSeekCostEstimatorRequiresACompleteCacheTokenSplit() {
    let event = UsageEvent(
        providerID: "deepseek",
        model: "deepseek-v4-flash",
        inputTokens: 1_000,
        outputTokens: 500,
        totalTokens: 1_500,
        confidence: .observed
    )

    #expect(DeepSeekCostEstimator.cost(for: event) == nil)
}

@Test func deepSeekCostEstimatorMakesMixedWindowsUnavailable() {
    let now = Date(timeIntervalSince1970: 1_704_067_200)
    let priced = UsageEvent(
        providerID: "deepseek",
        model: "deepseek-v4-flash",
        inputTokens: 1_000,
        outputTokens: 500,
        totalTokens: 1_500,
        cachedInputTokens: 0,
        uncachedInputTokens: 1_000,
        createdAt: now,
        confidence: .observed
    )
    let unpriced = UsageEvent(
        providerID: "deepseek",
        model: "unknown",
        inputTokens: 500,
        outputTokens: 250,
        totalTokens: 750,
        cachedInputTokens: 0,
        uncachedInputTokens: 500,
        createdAt: now,
        confidence: .observed
    )

    let summary = DeepSeekCostEstimator.summarize(events: [priced, unpriced], now: now)

    #expect(summary.todayCost == nil)
    #expect(summary.todayUnpricedEventCount == 1)
}

@Test func deepSeekCostEstimatorUsesExactV4ProPricing() throws {
    let event = UsageEvent(
        providerID: "deepseek",
        model: "deepseek-v4-pro",
        inputTokens: 2_000_000,
        outputTokens: 1_000_000,
        totalTokens: 3_000_000,
        cachedInputTokens: 1_000_000,
        uncachedInputTokens: 1_000_000,
        confidence: .observed
    )

    let cost = try #require(DeepSeekCostEstimator.cost(for: event))

    #expect(abs(cost - 1.308625) < 0.000001)
}
