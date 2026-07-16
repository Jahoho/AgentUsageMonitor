import Foundation

public struct DeepSeekBalanceResponse: Decodable, Equatable, Sendable {
    public let isAvailable: Bool
    public let balanceInfos: [DeepSeekBalanceInfo]

    public init(isAvailable: Bool, balanceInfos: [DeepSeekBalanceInfo]) {
        self.isAvailable = isAvailable
        self.balanceInfos = balanceInfos
    }

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }
}

public struct DeepSeekBalanceInfo: Decodable, Equatable, Sendable {
    public let currency: String
    public let totalBalance: String
    public let grantedBalance: String
    public let toppedUpBalance: String

    public init(
        currency: String,
        totalBalance: String,
        grantedBalance: String,
        toppedUpBalance: String
    ) {
        self.currency = currency
        self.totalBalance = totalBalance
        self.grantedBalance = grantedBalance
        self.toppedUpBalance = toppedUpBalance
    }

    enum CodingKeys: String, CodingKey {
        case currency
        case totalBalance = "total_balance"
        case grantedBalance = "granted_balance"
        case toppedUpBalance = "topped_up_balance"
    }
}

public struct DeepSeekBalanceAccount: Equatable, Sendable {
    public let id: String
    public let label: String
    public let isDefault: Bool
    public let response: DeepSeekBalanceResponse?
    public let errorMessage: String?

    public init(
        id: String,
        label: String,
        isDefault: Bool = false,
        response: DeepSeekBalanceResponse?,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.label = label
        self.isDefault = isDefault
        self.response = response
        self.errorMessage = errorMessage
    }
}

public enum DeepSeekSnapshotFactory {
    public static func snapshot(
        from response: DeepSeekBalanceResponse,
        usageSummary: UsageSummary = .empty,
        costSummary: UsageCostSummary = .empty,
        activity: [UsageActivityBucket] = [],
        events: [UsageEvent] = [],
        updatedAt: Date = Date()
    ) -> ProviderSnapshot {
        let account = DeepSeekBalanceAccount(
            id: "primary",
            label: "Primary",
            isDefault: true,
            response: response
        )

        return snapshot(
            from: [account],
            usageSummary: usageSummary,
            costSummary: costSummary,
            activity: activity,
            events: events,
            updatedAt: updatedAt
        )
    }

    public static func snapshot(
        from accounts: [DeepSeekBalanceAccount],
        usageSummary: UsageSummary = .empty,
        costSummary: UsageCostSummary = .empty,
        activity: [UsageActivityBucket] = [],
        events: [UsageEvent] = [],
        updatedAt: Date = Date()
    ) -> ProviderSnapshot {
        guard accounts.isEmpty == false else {
            return ProviderSnapshot(
                id: "deepseek",
                name: "DeepSeek",
                kind: .api,
                updatedAt: updatedAt,
                health: .needsSetup,
                headline: "Add a DeepSeek API key",
                metrics: [
                    UsageMetric(
                        id: "balance",
                        label: "Balance",
                        value: "Not configured",
                        detail: "Save one or more keys under Settings -> DeepSeek.",
                        confidence: .unavailable
                    )
                ],
                bars: [],
                activity: activity,
                notes: notes(for: []),
                actions: [
                    ProviderAction(
                        id: "deepseek-console",
                        title: "Open DeepSeek Console",
                        url: URL(string: "https://platform.deepseek.com/")
                    )
                ]
            )
        }

        let primaryAccount = accounts.first { $0.isDefault && $0.response != nil }
            ?? accounts.first { $0.response != nil }
            ?? accounts.first
        let primaryBalance = primaryAccount?.response?.balanceInfos.first
        let balanceValue = primaryBalance.map { "\($0.totalBalance) \($0.currency)" } ?? "No balance"
        let availableAccountCount = accounts.filter { $0.response?.isAvailable == true }.count
        let responseCount = accounts.filter { $0.response != nil }.count
        let health: ProviderHealth = availableAccountCount > 0 ? .ready : .error
        let headline = availableAccountCount > 0
            ? "\(availableAccountCount)/\(accounts.count) DeepSeek key(s) available"
            : "DeepSeek balance query failed"

        var metrics = [
            UsageMetric(
                id: "balance",
                label: "Balance",
                value: balanceValue,
                detail: primaryAccount.map { "Official DeepSeek /user/balance for \($0.label)" } ?? "Official DeepSeek /user/balance",
                confidence: primaryBalance == nil ? .unavailable : .official
            ),
            UsageMetric(
                id: "api-keys",
                label: "API keys",
                value: "\(accounts.count)",
                detail: "Configured DeepSeek API keys",
                confidence: .observed
            ),
            UsageMetric(
                id: "available-keys",
                label: "Available",
                value: "\(availableAccountCount)/\(accounts.count)",
                detail: "Keys with successful official balance checks",
                confidence: responseCount > 0 ? .official : .unavailable
            )
        ]

        if let primaryBalance {
            metrics.append(
                UsageMetric(
                    id: "granted",
                    label: "Granted",
                    value: "\(primaryBalance.grantedBalance) \(primaryBalance.currency)",
                    detail: "Promotional or granted balance",
                    confidence: .official
                )
            )
            metrics.append(
                UsageMetric(
                    id: "topped-up",
                    label: "Top-up",
                    value: "\(primaryBalance.toppedUpBalance) \(primaryBalance.currency)",
                    detail: "Paid top-up balance",
                    confidence: .official
                )
            )
        }

        metrics.append(
            UsageMetric(
                id: "today-cost",
                label: "Today cost",
                value: formatCurrency(costSummary.todayCost),
                detail: costDetail(
                    cost: costSummary.todayCost,
                    unpricedEventCount: costSummary.todayUnpricedEventCount
                ),
                confidence: costSummary.todayCost == nil ? .unavailable : .estimated
            )
        )
        metrics.append(
            UsageMetric(
                id: "30d-cost",
                label: "30d cost",
                value: formatCurrency(costSummary.thirtyDayCost),
                detail: costDetail(
                    cost: costSummary.thirtyDayCost,
                    unpricedEventCount: costSummary.thirtyDayUnpricedEventCount
                ),
                confidence: costSummary.thirtyDayCost == nil ? .unavailable : .estimated
            )
        )
        metrics.append(
            UsageMetric(
                id: "today-tokens",
                label: "Today tokens",
                value: UsageValueFormatter.tokens(usageSummary.todayTokens),
                detail: "Observed through local DeepSeek proxy",
                confidence: usageSummary.todayTokens > 0 ? .observed : .unavailable
            )
        )
        metrics.append(
            UsageMetric(
                id: "30d-tokens",
                label: "30d tokens",
                value: UsageValueFormatter.tokens(usageSummary.thirtyDayTokens),
                detail: "Observed through local DeepSeek proxy",
                confidence: usageSummary.thirtyDayTokens > 0 ? .observed : .unavailable
            )
        )
        metrics.append(
            UsageMetric(
                id: "latest-tokens",
                label: "Latest tokens",
                value: UsageValueFormatter.tokens(usageSummary.latestTokens),
                detail: "Most recent recorded response",
                confidence: usageSummary.latestTokens > 0 ? .observed : .unavailable
            )
        )
        metrics.append(
            UsageMetric(
                id: "top-model",
                label: "Top model",
                value: usageSummary.topModel,
                detail: "By observed token volume",
                confidence: usageSummary.topModel == "No requests yet" ? .unavailable : .observed
            )
        )

        let accountIDs = Set(accounts.map(\.id))
        var accountSnapshots = accounts.map { account in
            accountSnapshot(
                from: account,
                events: events.filter { $0.accountID == account.id },
                now: updatedAt
            )
        }
        let unattributedEvents = events.filter { event in
            guard let accountID = event.accountID else {
                return true
            }
            return accountIDs.contains(accountID) == false
        }
        if unattributedEvents.isEmpty == false {
            accountSnapshots.append(
                unattributedAccountSnapshot(events: unattributedEvents, now: updatedAt)
            )
        }

        return ProviderSnapshot(
            id: "deepseek",
            name: "DeepSeek",
            kind: .api,
            updatedAt: updatedAt,
            health: health,
            headline: headline,
            metrics: metrics,
            bars: [],
            activity: activity,
            accounts: accountSnapshots,
            notes: notes(for: accounts),
            actions: [
                ProviderAction(
                    id: "deepseek-console",
                    title: "Open DeepSeek Console",
                    url: URL(string: "https://platform.deepseek.com/")
                )
            ]
        )
    }

    private static func notes(for accounts: [DeepSeekBalanceAccount]) -> [String] {
        var notes = [
            "Balance comes from DeepSeek's official /user/balance API.",
            "DeepSeek public docs expose per-response token usage, not a public usage-history API matching the website dashboard, so saving an API key does not backfill website history.",
            "Today tokens are recorded only when requests use the local proxy.",
            "Proxy address: http://127.0.0.1:18491"
        ]

        let failures = accounts
            .filter { $0.response == nil }
            .prefix(3)
            .compactMap { account -> String? in
                guard let errorMessage = account.errorMessage else {
                    return nil
                }
                return "\(account.label): \(errorMessage)"
            }

        notes.append(contentsOf: failures)
        return notes
    }

    private static func accountSnapshot(
        from account: DeepSeekBalanceAccount,
        events: [UsageEvent],
        now: Date
    ) -> ProviderAccountSnapshot {
        let balance = account.response?.balanceInfos.first
        let balanceValue = balance.map { "\($0.totalBalance) \($0.currency)" } ?? "Unavailable"
        let health: ProviderHealth
        if account.response?.isAvailable == true {
            health = .ready
        } else if account.response != nil {
            health = .unavailable
        } else {
            health = .error
        }

        var metrics = [
            UsageMetric(
                id: "source",
                label: "Balance source",
                value: account.response == nil ? "Official API failed" : "Official API",
                detail: account.errorMessage ?? "DeepSeek GET /user/balance",
                confidence: account.response == nil ? .unavailable : .official
            ),
            UsageMetric(
                id: "account",
                label: "API key",
                value: account.label,
                detail: "Local label; DeepSeek's balance API does not return API key names",
                confidence: .observed
            ),
            UsageMetric(
                id: "balance",
                label: "Balance",
                value: balanceValue,
                detail: "Official DeepSeek /user/balance value for this key",
                confidence: balance == nil ? .unavailable : .official
            )
        ]

        if let balance {
            metrics.append(contentsOf: [
                UsageMetric(
                    id: "granted",
                    label: "Granted",
                    value: "\(balance.grantedBalance) \(balance.currency)",
                    detail: "Official granted balance",
                    confidence: .official
                ),
                UsageMetric(
                    id: "topped-up",
                    label: "Top-up",
                    value: "\(balance.toppedUpBalance) \(balance.currency)",
                    detail: "Official topped-up balance",
                    confidence: .official
                )
            ])
        }
        metrics.append(contentsOf: observedMetrics(events: events, now: now))

        let activity = events.isEmpty
            ? nil
            : UsageActivitySummarizer.todayHourlyBuckets(events: events, now: now)
        var notes = [
            "Token and model activity comes only from usage fields in actual DeepSeek responses captured by the local proxy.",
            "This observed activity is not DeepSeek account-wide history and is never backfilled or estimated."
        ]
        if let errorMessage = account.errorMessage {
            notes.append("Official balance sync failed: \(errorMessage)")
        }

        return ProviderAccountSnapshot(
            id: account.id,
            name: account.label,
            detail: account.isDefault ? "Local label; Default" : "Local label",
            isDefault: account.isDefault,
            health: health,
            metrics: metrics,
            activity: activity,
            activityTitle: activity == nil ? nil : "Today by hour",
            models: UsageModelSummarizer.summarize(events: events, now: now),
            notes: notes
        )
    }

    private static func unattributedAccountSnapshot(
        events: [UsageEvent],
        now: Date
    ) -> ProviderAccountSnapshot {
        let activity = UsageActivitySummarizer.todayHourlyBuckets(events: events, now: now)
        return ProviderAccountSnapshot(
            id: "unattributed",
            name: "Unattributed requests",
            detail: "Observed responses not linked to a currently saved key",
            health: .ready,
            metrics: [
                UsageMetric(
                    id: "source",
                    label: "Source",
                    value: "Observed responses",
                    detail: "Actual DeepSeek response usage captured by the local proxy",
                    confidence: .observed
                )
            ] + observedMetrics(events: events, now: now),
            activity: activity,
            activityTitle: "Today by hour",
            models: UsageModelSummarizer.summarize(events: events, now: now),
            notes: [
                "These requests had no matching saved credential ID, so the app does not assign them to a specific key."
            ]
        )
    }

    private static func observedMetrics(events: [UsageEvent], now: Date) -> [UsageMetric] {
        let summary = UsageSummarizer.summarize(events: events, now: now)
        let thirtyDaysAgo = now.addingTimeInterval(-30 * 24 * 3_600)
        let thirtyDayRequestCount = events.filter { $0.createdAt >= thirtyDaysAgo && $0.createdAt <= now }.count
        return [
            UsageMetric(
                id: "today-tokens",
                label: "Today tokens",
                value: UsageValueFormatter.tokens(summary.todayTokens),
                detail: "Exact usage fields from responses observed through the local proxy",
                confidence: summary.todayTokens > 0 ? .observed : .unavailable
            ),
            UsageMetric(
                id: "30d-tokens",
                label: "30d tokens",
                value: UsageValueFormatter.tokens(summary.thirtyDayTokens),
                detail: "Observed responses in the rolling 30-day window; not account-wide history",
                confidence: summary.thirtyDayTokens > 0 ? .observed : .unavailable
            ),
            UsageMetric(
                id: "30d-requests",
                label: "30d requests",
                value: "\(thirtyDayRequestCount)",
                detail: "Count of actual responses captured by the local proxy",
                confidence: thirtyDayRequestCount > 0 ? .observed : .unavailable
            ),
            UsageMetric(
                id: "top-model",
                label: "Top model",
                value: summary.topModel,
                detail: "By observed response token volume",
                confidence: summary.topModel == "No requests yet" ? .unavailable : .observed
            )
        ]
    }

    private static func costDetail(cost: Double?, unpricedEventCount: Int) -> String {
        if unpricedEventCount > 0 {
            return "Unavailable: \(unpricedEventCount) response(s) lacked an exact verified model price or token split"
        }
        guard cost != nil else {
            return "No observed responses with complete pricing inputs"
        }
        return "Observed response tokens priced from \(DeepSeekCostEstimator.pricingSource), verified \(DeepSeekCostEstimator.pricingVerifiedDate)"
    }

    private static func formatCurrency(_ value: Double?) -> String {
        guard let value else {
            return "Unavailable"
        }
        if value >= 1 {
            return String(format: "$%.2f", value)
        }
        if value > 0 {
            return String(format: "$%.4f", value)
        }
        return "$0.00"
    }
}
