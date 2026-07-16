import Foundation

public struct OpenRouterKeyResponse: Decodable, Equatable, Sendable {
    public let data: OpenRouterKeyInfo

    public init(data: OpenRouterKeyInfo) {
        self.data = data
    }
}

public struct OpenRouterKeyInfo: Decodable, Equatable, Sendable {
    public let label: String?
    public let limit: Double?
    public let limitRemaining: Double?
    public let limitReset: String?
    public let usage: Double
    public let usageDaily: Double
    public let usageWeekly: Double
    public let usageMonthly: Double
    public let byokUsage: Double?
    public let byokUsageDaily: Double?
    public let byokUsageWeekly: Double?
    public let byokUsageMonthly: Double?
    public let includeBYOKInLimit: Bool?
    public let isFreeTier: Bool?
    public let isManagementKey: Bool?
    public let isProvisioningKey: Bool?
    public let expiresAt: String?

    public init(
        label: String? = nil,
        limit: Double? = nil,
        limitRemaining: Double? = nil,
        limitReset: String? = nil,
        usage: Double,
        usageDaily: Double,
        usageWeekly: Double,
        usageMonthly: Double,
        byokUsage: Double? = nil,
        byokUsageDaily: Double? = nil,
        byokUsageWeekly: Double? = nil,
        byokUsageMonthly: Double? = nil,
        includeBYOKInLimit: Bool? = nil,
        isFreeTier: Bool? = nil,
        isManagementKey: Bool? = nil,
        isProvisioningKey: Bool? = nil,
        expiresAt: String? = nil
    ) {
        self.label = label
        self.limit = limit
        self.limitRemaining = limitRemaining
        self.limitReset = limitReset
        self.usage = usage
        self.usageDaily = usageDaily
        self.usageWeekly = usageWeekly
        self.usageMonthly = usageMonthly
        self.byokUsage = byokUsage
        self.byokUsageDaily = byokUsageDaily
        self.byokUsageWeekly = byokUsageWeekly
        self.byokUsageMonthly = byokUsageMonthly
        self.includeBYOKInLimit = includeBYOKInLimit
        self.isFreeTier = isFreeTier
        self.isManagementKey = isManagementKey
        self.isProvisioningKey = isProvisioningKey
        self.expiresAt = expiresAt
    }

    enum CodingKeys: String, CodingKey {
        case label
        case limit
        case limitRemaining = "limit_remaining"
        case limitReset = "limit_reset"
        case usage
        case usageDaily = "usage_daily"
        case usageWeekly = "usage_weekly"
        case usageMonthly = "usage_monthly"
        case byokUsage = "byok_usage"
        case byokUsageDaily = "byok_usage_daily"
        case byokUsageWeekly = "byok_usage_weekly"
        case byokUsageMonthly = "byok_usage_monthly"
        case includeBYOKInLimit = "include_byok_in_limit"
        case isFreeTier = "is_free_tier"
        case isManagementKey = "is_management_key"
        case isProvisioningKey = "is_provisioning_key"
        case expiresAt = "expires_at"
    }
}

public struct OpenRouterCreditsResponse: Decodable, Equatable, Sendable {
    public let data: OpenRouterCreditsInfo

    public init(data: OpenRouterCreditsInfo) {
        self.data = data
    }
}

public struct OpenRouterCreditsInfo: Decodable, Equatable, Sendable {
    public let totalCredits: Double
    public let totalUsage: Double

    public init(totalCredits: Double, totalUsage: Double) {
        self.totalCredits = totalCredits
        self.totalUsage = totalUsage
    }

    enum CodingKeys: String, CodingKey {
        case totalCredits = "total_credits"
        case totalUsage = "total_usage"
    }
}

public struct OpenRouterKeysResponse: Decodable, Equatable, Sendable {
    public let data: [OpenRouterManagedKeyInfo]

    public init(data: [OpenRouterManagedKeyInfo]) {
        self.data = data
    }
}

public struct OpenRouterManagedKeyInfo: Decodable, Equatable, Sendable {
    public let hash: String
    public let name: String?
    public let label: String?
    public let disabled: Bool
    public let limit: Double?
    public let limitRemaining: Double?
    public let limitReset: String?
    public let usage: Double
    public let usageDaily: Double
    public let usageWeekly: Double
    public let usageMonthly: Double
    public let byokUsage: Double?
    public let byokUsageDaily: Double?
    public let byokUsageWeekly: Double?
    public let byokUsageMonthly: Double?
    public let includeBYOKInLimit: Bool?
    public let workspaceID: String?
    public let expiresAt: String?

    public init(
        hash: String,
        name: String? = nil,
        label: String? = nil,
        disabled: Bool,
        limit: Double? = nil,
        limitRemaining: Double? = nil,
        limitReset: String? = nil,
        usage: Double,
        usageDaily: Double,
        usageWeekly: Double,
        usageMonthly: Double,
        byokUsage: Double? = nil,
        byokUsageDaily: Double? = nil,
        byokUsageWeekly: Double? = nil,
        byokUsageMonthly: Double? = nil,
        includeBYOKInLimit: Bool? = nil,
        workspaceID: String? = nil,
        expiresAt: String? = nil
    ) {
        self.hash = hash
        self.name = name
        self.label = label
        self.disabled = disabled
        self.limit = limit
        self.limitRemaining = limitRemaining
        self.limitReset = limitReset
        self.usage = usage
        self.usageDaily = usageDaily
        self.usageWeekly = usageWeekly
        self.usageMonthly = usageMonthly
        self.byokUsage = byokUsage
        self.byokUsageDaily = byokUsageDaily
        self.byokUsageWeekly = byokUsageWeekly
        self.byokUsageMonthly = byokUsageMonthly
        self.includeBYOKInLimit = includeBYOKInLimit
        self.workspaceID = workspaceID
        self.expiresAt = expiresAt
    }

    public var keyInfo: OpenRouterKeyInfo {
        OpenRouterKeyInfo(
            label: label,
            limit: limit,
            limitRemaining: limitRemaining,
            limitReset: limitReset,
            usage: usage,
            usageDaily: usageDaily,
            usageWeekly: usageWeekly,
            usageMonthly: usageMonthly,
            byokUsage: byokUsage,
            byokUsageDaily: byokUsageDaily,
            byokUsageWeekly: byokUsageWeekly,
            byokUsageMonthly: byokUsageMonthly,
            includeBYOKInLimit: includeBYOKInLimit,
            expiresAt: expiresAt
        )
    }

    enum CodingKeys: String, CodingKey {
        case hash
        case name
        case label
        case disabled
        case limit
        case limitRemaining = "limit_remaining"
        case limitReset = "limit_reset"
        case usage
        case usageDaily = "usage_daily"
        case usageWeekly = "usage_weekly"
        case usageMonthly = "usage_monthly"
        case byokUsage = "byok_usage"
        case byokUsageDaily = "byok_usage_daily"
        case byokUsageWeekly = "byok_usage_weekly"
        case byokUsageMonthly = "byok_usage_monthly"
        case includeBYOKInLimit = "include_byok_in_limit"
        case workspaceID = "workspace_id"
        case expiresAt = "expires_at"
    }
}

public struct OpenRouterActivityResponse: Decodable, Equatable, Sendable {
    public let data: [OpenRouterActivityItem]

    public init(data: [OpenRouterActivityItem]) {
        self.data = data
    }
}

public struct OpenRouterActivityItem: Decodable, Equatable, Sendable {
    public let date: String
    public let endpointID: String?
    public let model: String
    public let modelPermaslug: String?
    public let providerName: String?
    public let requests: Int
    public let promptTokens: Int
    public let completionTokens: Int
    public let reasoningTokens: Int
    public let usage: Double
    public let byokUsageInference: Double?

    public init(
        date: String,
        endpointID: String? = nil,
        model: String,
        modelPermaslug: String? = nil,
        providerName: String? = nil,
        requests: Int,
        promptTokens: Int,
        completionTokens: Int,
        reasoningTokens: Int,
        usage: Double,
        byokUsageInference: Double? = nil
    ) {
        self.date = date
        self.endpointID = endpointID
        self.model = model
        self.modelPermaslug = modelPermaslug
        self.providerName = providerName
        self.requests = requests
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.reasoningTokens = reasoningTokens
        self.usage = usage
        self.byokUsageInference = byokUsageInference
    }

    enum CodingKeys: String, CodingKey {
        case date
        case endpointID = "endpoint_id"
        case model
        case modelPermaslug = "model_permaslug"
        case providerName = "provider_name"
        case requests
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case reasoningTokens = "reasoning_tokens"
        case usage
        case byokUsageInference = "byok_usage_inference"
    }
}

public struct OpenRouterOfficialUsage: Equatable, Sendable {
    public let key: OpenRouterKeyInfo
    public let credits: OpenRouterCreditsInfo?

    public init(key: OpenRouterKeyInfo, credits: OpenRouterCreditsInfo? = nil) {
        self.key = key
        self.credits = credits
    }
}

public struct OpenRouterAccountUsage: Equatable, Sendable {
    public let id: String
    public let name: String
    public let detail: String
    public let sourceDetail: String
    public let nameConfidence: UsageConfidence
    public let isDefault: Bool
    public let key: OpenRouterKeyInfo
    public let activity: [OpenRouterActivityItem]?
    public let activityError: String?
    public let activityNote: String?

    public init(
        id: String,
        name: String,
        detail: String,
        sourceDetail: String = "OpenRouter GET /api/v1/key",
        nameConfidence: UsageConfidence = .official,
        isDefault: Bool = false,
        key: OpenRouterKeyInfo,
        activity: [OpenRouterActivityItem]? = nil,
        activityError: String? = nil,
        activityNote: String? = nil
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.sourceDetail = sourceDetail
        self.nameConfidence = nameConfidence
        self.isDefault = isDefault
        self.key = key
        self.activity = activity
        self.activityError = activityError
        self.activityNote = activityNote
    }
}

public enum OpenRouterSnapshotFactory {
    public static func snapshot(
        from usage: OpenRouterOfficialUsage,
        additionalNotes: [String] = [],
        updatedAt: Date = Date()
    ) -> ProviderSnapshot {
        let accountUsage = OpenRouterAccountUsage(
            id: "current-key",
            name: displayLabel(usage.key.label),
            detail: usage.key.isManagementKey == true ? "Official management key" : "Official current API key",
            isDefault: true,
            key: usage.key
        )
        let account = accountSnapshot(from: accountUsage)
        return snapshot(
            accounts: [account],
            primaryAccountID: account.id,
            credits: usage.credits,
            additionalNotes: additionalNotes,
            updatedAt: updatedAt
        )
    }

    public static func snapshot(
        accounts: [ProviderAccountSnapshot],
        primaryAccountID: String? = nil,
        credits: OpenRouterCreditsInfo? = nil,
        additionalNotes: [String] = [],
        updatedAt: Date = Date()
    ) -> ProviderSnapshot {
        let primaryAccount = accounts.first { $0.id == primaryAccountID }
            ?? accounts.first { $0.isDefault && $0.health == .ready }
            ?? accounts.first { $0.health == .ready }
            ?? accounts.first
        var metrics = primaryAccount?.metrics ?? []

        if let credits {
            metrics.append(contentsOf: creditMetrics(credits))
        }

        var notes = [
            "Spend, limits, key names, and activity shown as Official come only from OpenRouter APIs.",
            "Per-model activity is available only when a saved management key authorizes /api/v1/keys and /api/v1/activity.",
            "The management key catalog covers OpenRouter's default workspace; separately saved keys remain visible as local credential profiles.",
            "No cached, locally observed, or estimated OpenRouter usage is mixed into these values."
        ]
        if credits != nil {
            notes.append("Account credit totals come from the official /api/v1/credits API.")
        }
        notes.append(contentsOf: additionalNotes)

        let hasReadyAccount = accounts.contains { $0.health == .ready }
        return ProviderSnapshot(
            id: "openrouter",
            name: "OpenRouter",
            kind: .api,
            updatedAt: updatedAt,
            health: hasReadyAccount ? .ready : .error,
            headline: hasReadyAccount ? "Official OpenRouter usage synced" : "OpenRouter official usage sync failed",
            metrics: metrics,
            bars: primaryAccount?.bars ?? [],
            activity: primaryAccount?.activity,
            accounts: accounts,
            notes: notes,
            actions: actions
        )
    }

    public static func accountSnapshot(from usage: OpenRouterAccountUsage) -> ProviderAccountSnapshot {
        let key = usage.key
        var metrics = [
            UsageMetric(
                id: "source",
                label: "Source",
                value: "Official API",
                detail: usage.sourceDetail,
                confidence: .official
            ),
            UsageMetric(
                id: "account",
                label: "API key",
                value: usage.name,
                detail: usage.detail,
                confidence: usage.nameConfidence
            ),
            UsageMetric(
                id: "today-cost",
                label: "Today spend",
                value: formatUSD(key.usageDaily),
                detail: "Official usage_daily value",
                confidence: .official
            ),
            UsageMetric(
                id: "week-cost",
                label: "Week spend",
                value: formatUSD(key.usageWeekly),
                detail: "Official usage_weekly value",
                confidence: .official
            ),
            UsageMetric(
                id: "month-cost",
                label: "Month spend",
                value: formatUSD(key.usageMonthly),
                detail: "Official usage_monthly value",
                confidence: .official
            ),
            UsageMetric(
                id: "all-time-cost",
                label: "All-time spend",
                value: formatUSD(key.usage),
                detail: "Official usage value for this key",
                confidence: .official
            )
        ]

        if let limit = key.limit {
            metrics.append(
                UsageMetric(
                    id: "key-limit",
                    label: "Key limit",
                    value: formatUSD(limit),
                    detail: limitDescription(key.limitReset),
                    confidence: .official
                )
            )
        } else {
            metrics.append(
                UsageMetric(
                    id: "key-limit",
                    label: "Key limit",
                    value: "Unlimited",
                    detail: "OpenRouter returned no key spending limit",
                    confidence: .official
                )
            )
        }

        if let remaining = key.limitRemaining {
            metrics.append(
                UsageMetric(
                    id: "key-remaining",
                    label: "Key remaining",
                    value: formatUSD(remaining),
                    detail: "Official limit_remaining value",
                    confidence: .official
                )
            )
        }

        if let byokUsageMonthly = key.byokUsageMonthly,
           key.includeBYOKInLimit == true || byokUsageMonthly != 0 {
            metrics.append(
                UsageMetric(
                    id: "byok-month-cost",
                    label: "BYOK month",
                    value: formatUSD(byokUsageMonthly),
                    detail: "Official byok_usage_monthly value",
                    confidence: .official
                )
            )
        }

        let activity = usage.activity.map(activityBuckets)
        let models = usage.activity.map(modelSummaries) ?? []
        var notes: [String] = []
        if let activityError = usage.activityError {
            notes.append("Official per-model activity sync failed: \(activityError)")
        } else if let activityNote = usage.activityNote {
            notes.append(activityNote)
        } else if let activity = usage.activity, activity.isEmpty {
            notes.append("OpenRouter returned no activity for this key in the last 30 completed UTC days.")
        } else if usage.activity == nil {
            notes.append("Official per-model activity requires a management key.")
        }

        return ProviderAccountSnapshot(
            id: usage.id,
            name: usage.name,
            detail: usage.detail,
            isDefault: usage.isDefault,
            health: .ready,
            metrics: metrics,
            bars: limitBars(for: key),
            activity: activity,
            activityTitle: activity == nil ? nil : "Last 30 completed UTC days",
            models: models,
            notes: notes,
        )
    }

    public static var actions: [ProviderAction] {
        [
            ProviderAction(
                id: "openrouter-activity",
                title: "Open OpenRouter Activity",
                url: URL(string: "https://openrouter.ai/activity")
            ),
            ProviderAction(
                id: "openrouter-keys",
                title: "Open OpenRouter API Keys",
                url: URL(string: "https://openrouter.ai/settings/keys")
            )
        ]
    }

    private static func creditMetrics(_ credits: OpenRouterCreditsInfo) -> [UsageMetric] {
        [
            UsageMetric(
                id: "credit-balance",
                label: "Credit balance",
                value: formatUSD(credits.totalCredits - credits.totalUsage),
                detail: "Official total credits minus official total usage",
                confidence: .official
            ),
            UsageMetric(
                id: "total-credits",
                label: "Total credits",
                value: formatUSD(credits.totalCredits),
                detail: "Official /api/v1/credits total_credits value",
                confidence: .official
            ),
            UsageMetric(
                id: "account-usage",
                label: "Account usage",
                value: formatUSD(credits.totalUsage),
                detail: "Official /api/v1/credits total_usage value",
                confidence: .official
            )
        ]
    }

    private static func limitBars(for key: OpenRouterKeyInfo) -> [UsageBar] {
        guard let limit = key.limit, limit > 0, let remaining = key.limitRemaining else {
            return []
        }

        let remainingFraction = min(max(remaining / limit, 0), 1)
        let used = max(0, limit - remaining)
        return [
            UsageBar(
                id: "openrouter-key-limit",
                label: "API key limit",
                remainingFraction: remainingFraction,
                usedText: "\(formatUSD(used)) used of \(formatUSD(limit))",
                resetText: limitDescription(key.limitReset),
                confidence: .official
            )
        ]
    }

    private static func displayLabel(_ label: String?) -> String {
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Current key" : trimmed
    }

    private static func limitDescription(_ reset: String?) -> String {
        switch reset?.lowercased() {
        case "daily":
            return "Resets daily at 00:00 UTC"
        case "weekly":
            return "Resets Monday at 00:00 UTC"
        case "monthly":
            return "Resets monthly at 00:00 UTC"
        case .some(let value):
            return "Reset period: \(value)"
        case nil:
            return "No automatic reset"
        }
    }

    private static func formatUSD(_ value: Double) -> String {
        if value == 0 {
            return "$0.00"
        }
        if abs(value) < 0.01 {
            return String(format: "$%.4f", value)
        }
        return String(format: "$%.2f", value)
    }

    private static func activityBuckets(_ items: [OpenRouterActivityItem]) -> [UsageActivityBucket] {
        let grouped = Dictionary(grouping: items, by: \.date)
        return grouped.keys.sorted().map { date in
            let tokens = grouped[date, default: []].reduce(0) {
                $0 + max(0, $1.promptTokens) + max(0, $1.completionTokens)
            }
            return UsageActivityBucket(
                id: "openrouter-day-\(date)",
                label: displayDate(date),
                axisLabel: axisDate(date),
                value: Double(tokens),
                valueText: UsageValueFormatter.tokens(tokens),
                confidence: .official
            )
        }
    }

    private static func modelSummaries(_ items: [OpenRouterActivityItem]) -> [UsageModelSummary] {
        struct ModelKey: Hashable {
            let model: String
            let permaslug: String?
        }

        let grouped = Dictionary(grouping: items) {
            ModelKey(model: $0.model, permaslug: $0.modelPermaslug)
        }
        return grouped.map { key, modelItems in
            let providerNames = Set(modelItems.compactMap(\.providerName)).sorted()
            let inputTokens = modelItems.reduce(0) { $0 + max(0, $1.promptTokens) }
            let outputTokens = modelItems.reduce(0) { $0 + max(0, $1.completionTokens) }
            return UsageModelSummary(
                id: [key.model, key.permaslug].compactMap(\.self).joined(separator: "|"),
                model: key.model,
                providerNames: providerNames,
                requestCount: modelItems.reduce(0) { $0 + max(0, $1.requests) },
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                reasoningTokens: modelItems.reduce(0) { $0 + max(0, $1.reasoningTokens) },
                totalTokens: inputTokens + outputTokens,
                spendUSD: modelItems.reduce(0) { $0 + max(0, $1.usage) },
                latestAt: modelItems.compactMap { parseDate($0.date) }.max(),
                confidence: .official
            )
        }
        .sorted {
            if $0.totalTokens == $1.totalTokens {
                return $0.model.localizedCaseInsensitiveCompare($1.model) == .orderedAscending
            }
            return $0.totalTokens > $1.totalTokens
        }
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func displayDate(_ value: String) -> String {
        guard let date = parseDate(value) else {
            return value
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private static func axisDate(_ value: String) -> String? {
        guard let date = parseDate(value) else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }
}
