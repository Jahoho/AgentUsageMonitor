import Foundation

public struct UsageEvent: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let providerID: String
    public let accountID: String?
    public let model: String
    public let inputTokens: Int
    public let outputTokens: Int
    public let totalTokens: Int
    public let cachedInputTokens: Int?
    public let uncachedInputTokens: Int?
    public let createdAt: Date
    public let confidence: UsageConfidence

    public init(
        id: UUID = UUID(),
        providerID: String,
        accountID: String? = nil,
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        totalTokens: Int,
        cachedInputTokens: Int? = nil,
        uncachedInputTokens: Int? = nil,
        createdAt: Date = Date(),
        confidence: UsageConfidence
    ) {
        self.id = id
        self.providerID = providerID
        self.accountID = accountID
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.cachedInputTokens = cachedInputTokens
        self.uncachedInputTokens = uncachedInputTokens
        self.createdAt = createdAt
        self.confidence = confidence
    }
}

public struct UsageSummary: Equatable, Sendable {
    public let todayTokens: Int
    public let thirtyDayTokens: Int
    public let latestTokens: Int
    public let topModel: String

    public init(todayTokens: Int, thirtyDayTokens: Int, latestTokens: Int, topModel: String) {
        self.todayTokens = todayTokens
        self.thirtyDayTokens = thirtyDayTokens
        self.latestTokens = latestTokens
        self.topModel = topModel
    }

    public static let empty = UsageSummary(
        todayTokens: 0,
        thirtyDayTokens: 0,
        latestTokens: 0,
        topModel: "No requests yet"
    )
}

public enum UsageTokenAccounting: Sendable {
    case reportedTotal
    case excludingCachedInput

    fileprivate func tokenCount(for event: UsageEvent) -> Int {
        switch self {
        case .reportedTotal:
            return max(0, event.totalTokens)
        case .excludingCachedInput:
            let reportedTotal = max(0, event.totalTokens)
            let cachedInput = min(
                max(0, event.cachedInputTokens ?? 0),
                max(0, event.inputTokens)
            )
            return max(0, reportedTotal - cachedInput)
        }
    }
}

public enum UsageEventParser {
    public static func deepSeekEvent(
        from data: Data,
        accountID: String? = nil,
        createdAt: Date = Date()
    ) -> UsageEvent? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let usage = json["usage"] as? [String: Any]
        else {
            return nil
        }

        let model = json["model"] as? String ?? "unknown"
        let inputTokens = usage["prompt_tokens"] as? Int ?? 0
        let outputTokens = usage["completion_tokens"] as? Int ?? 0
        let totalTokens = usage["total_tokens"] as? Int ?? inputTokens + outputTokens
        let cachedInputTokens = usage["prompt_cache_hit_tokens"] as? Int
        let uncachedInputTokens = usage["prompt_cache_miss_tokens"] as? Int

        guard totalTokens > 0 else {
            return nil
        }

        return UsageEvent(
            providerID: "deepseek",
            accountID: accountID,
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens,
            cachedInputTokens: cachedInputTokens,
            uncachedInputTokens: uncachedInputTokens,
            createdAt: createdAt,
            confidence: .observed
        )
    }

    public static func deepSeekEventFromSSE(
        from data: Data,
        accountID: String? = nil,
        createdAt: Date = Date()
    ) -> UsageEvent? {
        guard let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        var latestEvent: UsageEvent?
        let blocks = text.components(separatedBy: "\n\n")

        for block in blocks {
            let payload = block
                .split(whereSeparator: \.isNewline)
                .compactMap { line -> String? in
                    let trimmedLine = line.trimmingCharacters(in: .whitespaces)
                    guard trimmedLine.hasPrefix("data:") else {
                        return nil
                    }
                    return String(trimmedLine.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                }
                .joined(separator: "\n")

            guard payload.isEmpty == false, payload != "[DONE]" else {
                continue
            }

            if let event = deepSeekEvent(from: Data(payload.utf8), accountID: accountID, createdAt: createdAt) {
                latestEvent = event
            }
        }

        return latestEvent
    }
}

public struct UsageCostSummary: Equatable, Sendable {
    public let todayCost: Double?
    public let thirtyDayCost: Double?
    public let todayUnpricedEventCount: Int
    public let thirtyDayUnpricedEventCount: Int

    public init(
        todayCost: Double?,
        thirtyDayCost: Double?,
        todayUnpricedEventCount: Int = 0,
        thirtyDayUnpricedEventCount: Int = 0
    ) {
        self.todayCost = todayCost
        self.thirtyDayCost = thirtyDayCost
        self.todayUnpricedEventCount = todayUnpricedEventCount
        self.thirtyDayUnpricedEventCount = thirtyDayUnpricedEventCount
    }

    public static let empty = UsageCostSummary(todayCost: nil, thirtyDayCost: nil)
}

public enum DeepSeekCostEstimator {
    public static let pricingSource = "DeepSeek Models & Pricing"
    public static let pricingVerifiedDate = "2026-07-15"

    public static func summarize(
        events: [UsageEvent],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> UsageCostSummary {
        let startOfToday = calendar.startOfDay(for: now)
        let thirtyDaysAgo = now.addingTimeInterval(-30 * 24 * 3_600)
        let todayEvents = events.filter { $0.createdAt >= startOfToday && $0.createdAt <= now }
        let thirtyDayEvents = events.filter { $0.createdAt >= thirtyDaysAgo && $0.createdAt <= now }
        let todaySummary = strictCostSummary(for: todayEvents)
        let thirtyDaySummary = strictCostSummary(for: thirtyDayEvents)

        return UsageCostSummary(
            todayCost: todaySummary.cost,
            thirtyDayCost: thirtyDaySummary.cost,
            todayUnpricedEventCount: todaySummary.unpricedEventCount,
            thirtyDayUnpricedEventCount: thirtyDaySummary.unpricedEventCount
        )
    }

    public static func cost(for event: UsageEvent) -> Double? {
        guard let price = pricePerMillionTokens(for: event.model),
              let inputSplit = validatedInputSplit(for: event)
        else {
            return nil
        }

        let inputCost = (Double(inputSplit.uncached) / 1_000_000) * price.inputCacheMiss
            + (Double(inputSplit.cached) / 1_000_000) * price.inputCacheHit
        let outputCost = (Double(event.outputTokens) / 1_000_000) * price.output
        return inputCost + outputCost
    }

    private static func strictCostSummary(for events: [UsageEvent]) -> (cost: Double?, unpricedEventCount: Int) {
        guard events.isEmpty == false else {
            return (nil, 0)
        }

        let costs = events.map(cost(for:))
        let unpricedEventCount = costs.filter { $0 == nil }.count
        guard unpricedEventCount == 0 else {
            return (nil, unpricedEventCount)
        }

        return (costs.compactMap(\.self).reduce(0, +), 0)
    }

    private static func validatedInputSplit(for event: UsageEvent) -> (cached: Int, uncached: Int)? {
        guard event.inputTokens >= 0, event.outputTokens >= 0, event.totalTokens >= 0 else {
            return nil
        }

        let (reportedTotal, totalOverflow) = event.inputTokens.addingReportingOverflow(event.outputTokens)
        guard totalOverflow == false, reportedTotal == event.totalTokens else {
            return nil
        }

        switch (event.cachedInputTokens, event.uncachedInputTokens) {
        case (nil, nil):
            return nil
        case (.some(let cached), nil):
            guard cached >= 0, cached <= event.inputTokens else {
                return nil
            }
            return (cached: cached, uncached: event.inputTokens - cached)
        case (nil, .some(let uncached)):
            guard uncached >= 0, uncached <= event.inputTokens else {
                return nil
            }
            return (cached: event.inputTokens - uncached, uncached: uncached)
        case (.some(let cached), .some(let uncached)):
            guard cached >= 0, uncached >= 0 else {
                return nil
            }
            let (inputTotal, inputOverflow) = cached.addingReportingOverflow(uncached)
            guard inputOverflow == false, inputTotal == event.inputTokens else {
                return nil
            }
            return (cached: cached, uncached: uncached)
        }
    }

    private static func pricePerMillionTokens(
        for model: String
    ) -> (inputCacheHit: Double, inputCacheMiss: Double, output: Double)? {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "deepseek-v4-pro":
            return (inputCacheHit: 0.003625, inputCacheMiss: 0.435, output: 0.87)
        case "deepseek-v4-flash", "deepseek-chat", "deepseek-reasoner":
            return (inputCacheHit: 0.0028, inputCacheMiss: 0.14, output: 0.28)
        default:
            return nil
        }
    }
}

public enum UsageSummarizer {
    public static func summarize(
        events: [UsageEvent],
        now: Date = Date(),
        calendar: Calendar = .current,
        accounting: UsageTokenAccounting = .reportedTotal
    ) -> UsageSummary {
        let startOfToday = calendar.startOfDay(for: now)
        let thirtyDaysAgo = now.addingTimeInterval(-30 * 24 * 3_600)

        let todayTokens = events
            .filter { $0.createdAt >= startOfToday }
            .reduce(0) { $0 + accounting.tokenCount(for: $1) }

        let thirtyDayTokens = events
            .filter { $0.createdAt >= thirtyDaysAgo }
            .reduce(0) { $0 + accounting.tokenCount(for: $1) }

        let latestTokens = events
            .sorted { $0.createdAt > $1.createdAt }
            .first
            .map { accounting.tokenCount(for: $0) } ?? 0

        let topModel = events
            .reduce(into: [String: Int]()) { counts, event in
                let tokenCount = accounting.tokenCount(for: event)
                if tokenCount > 0 {
                    counts[event.model, default: 0] += tokenCount
                }
            }
            .max { $0.value < $1.value }?
            .key ?? "No requests yet"

        return UsageSummary(
            todayTokens: todayTokens,
            thirtyDayTokens: thirtyDayTokens,
            latestTokens: latestTokens,
            topModel: topModel
        )
    }
}

public enum UsageActivitySummarizer {
    public static func todayHourlyBuckets(
        events: [UsageEvent],
        now: Date = Date(),
        calendar: Calendar = .current,
        accounting: UsageTokenAccounting = .reportedTotal
    ) -> [UsageActivityBucket] {
        let startOfDay = calendar.startOfDay(for: now)

        return (0..<24).map { hour in
            let start = calendar.date(byAdding: .hour, value: hour, to: startOfDay) ?? startOfDay
            let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start
            let tokens = events
                .filter { $0.createdAt >= start && $0.createdAt < end }
                .reduce(0) { $0 + accounting.tokenCount(for: $1) }

            return UsageActivityBucket(
                id: "hour-\(hour)",
                label: String(format: "%02d:00", hour),
                value: Double(tokens),
                valueText: UsageValueFormatter.tokens(tokens),
                confidence: tokens > 0 ? .observed : .unavailable
            )
        }
    }
}

public enum UsageModelSummarizer {
    public static func summarize(
        events: [UsageEvent],
        now: Date = Date(),
        window: TimeInterval = 30 * 24 * 3_600
    ) -> [UsageModelSummary] {
        let start = now.addingTimeInterval(-window)
        let recentEvents = events.filter { $0.createdAt >= start && $0.createdAt <= now }
        let groupedEvents = Dictionary(grouping: recentEvents, by: \.model)

        return groupedEvents.map { model, modelEvents in
            UsageModelSummary(
                id: model,
                model: model,
                requestCount: modelEvents.count,
                inputTokens: modelEvents.reduce(0) { $0 + max(0, $1.inputTokens) },
                outputTokens: modelEvents.reduce(0) { $0 + max(0, $1.outputTokens) },
                totalTokens: modelEvents.reduce(0) { $0 + max(0, $1.totalTokens) },
                latestAt: modelEvents.map(\.createdAt).max(),
                confidence: .observed
            )
        }
        .sorted {
            if $0.totalTokens == $1.totalTokens {
                return $0.model.localizedCaseInsensitiveCompare($1.model) == .orderedAscending
            }
            return $0.totalTokens > $1.totalTokens
        }
    }
}
