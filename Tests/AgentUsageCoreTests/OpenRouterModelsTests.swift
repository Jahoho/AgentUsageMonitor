import Foundation
import Testing
@testable import AgentUsageCore

@Test func openRouterKeyResponseDecodesOfficialUsageFields() throws {
    let data = Data(
        #"""
        {
          "data": {
            "label": "sk-or-v1-test...1234",
            "limit": 100,
            "limit_remaining": 25,
            "limit_reset": "monthly",
            "usage": 80.5,
            "usage_daily": 1.25,
            "usage_weekly": 12.5,
            "usage_monthly": 75,
            "byok_usage": 2,
            "byok_usage_daily": 0.1,
            "byok_usage_weekly": 0.5,
            "byok_usage_monthly": 1.5,
            "include_byok_in_limit": true,
            "is_free_tier": false,
            "is_management_key": false,
            "is_provisioning_key": false,
            "expires_at": null
          }
        }
        """#.utf8
    )

    let response = try JSONDecoder().decode(OpenRouterKeyResponse.self, from: data)

    #expect(response.data.usageDaily == 1.25)
    #expect(response.data.usageWeekly == 12.5)
    #expect(response.data.usageMonthly == 75)
    #expect(response.data.limitRemaining == 25)
    #expect(response.data.includeBYOKInLimit == true)
}

@Test func openRouterKeyResponseRejectsMissingOfficialUsageWindow() {
    let data = Data(
        #"""
        {
          "data": {
            "usage": 80.5,
            "usage_daily": 1.25,
            "usage_weekly": 12.5
          }
        }
        """#.utf8
    )

    #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(OpenRouterKeyResponse.self, from: data)
    }
}

@Test func openRouterSnapshotMapsOfficialSpendAndLimitWithoutEstimating() throws {
    let snapshot = OpenRouterSnapshotFactory.snapshot(
        from: OpenRouterOfficialUsage(
            key: openRouterKeyInfo(
                limit: 100,
                limitRemaining: 25,
                limitReset: "monthly"
            )
        )
    )

    #expect(snapshot.health == .ready)
    #expect(snapshot.metrics.first { $0.id == "today-cost" }?.value == "$1.25")
    #expect(snapshot.metrics.first { $0.id == "week-cost" }?.value == "$12.50")
    #expect(snapshot.metrics.first { $0.id == "month-cost" }?.value == "$75.00")
    #expect(snapshot.metrics.first { $0.id == "all-time-cost" }?.value == "$80.50")
    #expect(snapshot.metrics.allSatisfy { $0.confidence == .official })

    let bar = try #require(snapshot.bars.first)
    #expect(bar.remainingFraction == 0.25)
    #expect(bar.usedText == "$75.00 used of $100.00")
    #expect(bar.resetText == "Resets monthly at 00:00 UTC")
    #expect(snapshot.activity == nil)
    #expect(snapshot.notes.contains { $0.contains("management key") })
}

@Test func openRouterSnapshotTreatsNullLimitAsOfficialUnlimited() {
    let snapshot = OpenRouterSnapshotFactory.snapshot(
        from: OpenRouterOfficialUsage(key: openRouterKeyInfo())
    )

    #expect(snapshot.metrics.first { $0.id == "key-limit" }?.value == "Unlimited")
    #expect(snapshot.bars.isEmpty)
}

@Test func openRouterSnapshotDoesNotInventMissingBYOKSpend() {
    let key = OpenRouterKeyInfo(
        usage: 80.5,
        usageDaily: 1.25,
        usageWeekly: 12.5,
        usageMonthly: 75,
        includeBYOKInLimit: true
    )
    let snapshot = OpenRouterSnapshotFactory.snapshot(
        from: OpenRouterOfficialUsage(key: key)
    )

    #expect(snapshot.metrics.contains { $0.id == "byok-month-cost" } == false)
}

@Test func openRouterSnapshotAddsOfficialManagementCreditTotals() {
    let snapshot = OpenRouterSnapshotFactory.snapshot(
        from: OpenRouterOfficialUsage(
            key: openRouterKeyInfo(isManagementKey: true),
            credits: OpenRouterCreditsInfo(totalCredits: 250, totalUsage: 80.5)
        )
    )

    #expect(snapshot.metrics.first { $0.id == "credit-balance" }?.value == "$169.50")
    #expect(snapshot.metrics.first { $0.id == "total-credits" }?.value == "$250.00")
    #expect(snapshot.metrics.first { $0.id == "account-usage" }?.value == "$80.50")
}

@Test func openRouterManagedKeysResponseDecodesOfficialNamesAndHashes() throws {
    let data = Data(
        #"{"data":[{"hash":"abc123","name":"Production","label":"Production API Key","disabled":false,"limit":100,"limit_remaining":74.5,"limit_reset":"monthly","usage":25.5,"usage_daily":1.5,"usage_weekly":10.5,"usage_monthly":25.5,"workspace_id":"workspace-1","expires_at":null}]}"#.utf8
    )

    let response = try JSONDecoder().decode(OpenRouterKeysResponse.self, from: data)
    let key = try #require(response.data.first)

    #expect(key.hash == "abc123")
    #expect(key.name == "Production")
    #expect(key.label == "Production API Key")
    #expect(key.usageMonthly == 25.5)
    #expect(key.keyInfo.limitRemaining == 74.5)
}

@Test func openRouterActivityResponseRequiresOfficialTokenFields() throws {
    let data = Data(
        #"{"data":[{"date":"2026-07-13","endpoint_id":"endpoint-1","model":"openai/gpt-4.1","model_permaslug":"openai/gpt-4.1-2025-04-14","provider_name":"OpenAI","requests":5,"prompt_tokens":50,"completion_tokens":125,"reasoning_tokens":25,"usage":0.015,"byok_usage_inference":0.012}]}"#.utf8
    )

    let response = try JSONDecoder().decode(OpenRouterActivityResponse.self, from: data)
    let item = try #require(response.data.first)

    #expect(item.model == "openai/gpt-4.1")
    #expect(item.requests == 5)
    #expect(item.promptTokens == 50)
    #expect(item.completionTokens == 125)
    #expect(item.reasoningTokens == 25)
    #expect(item.usage == 0.015)
}

@Test func openRouterAccountSnapshotAggregatesOnlyOfficialActivityRows() throws {
    let account = OpenRouterSnapshotFactory.accountSnapshot(
        from: OpenRouterAccountUsage(
            id: "managed-abc123",
            name: "Production",
            detail: "Discovered by official management API",
            key: openRouterKeyInfo(),
            activity: [
                OpenRouterActivityItem(
                    date: "2026-07-12",
                    model: "openai/gpt-4.1",
                    modelPermaslug: "openai/gpt-4.1-2025-04-14",
                    providerName: "OpenAI",
                    requests: 2,
                    promptTokens: 100,
                    completionTokens: 200,
                    reasoningTokens: 50,
                    usage: 0.03
                ),
                OpenRouterActivityItem(
                    date: "2026-07-13",
                    model: "openai/gpt-4.1",
                    modelPermaslug: "openai/gpt-4.1-2025-04-14",
                    providerName: "OpenAI",
                    requests: 3,
                    promptTokens: 10,
                    completionTokens: 20,
                    reasoningTokens: 5,
                    usage: 0.01
                )
            ]
        )
    )

    #expect(account.activityTitle == "Last 30 completed UTC days")
    #expect(account.activity?.map(\.value) == [300, 30])
    #expect(account.activity?.allSatisfy { $0.confidence == .official } == true)

    let model = try #require(account.models.first)
    #expect(model.requestCount == 5)
    #expect(model.inputTokens == 110)
    #expect(model.outputTokens == 220)
    #expect(model.reasoningTokens == 55)
    #expect(model.totalTokens == 330)
    #expect(model.spendUSD == 0.04)
    #expect(model.confidence == .official)
}

private func openRouterKeyInfo(
    limit: Double? = nil,
    limitRemaining: Double? = nil,
    limitReset: String? = nil,
    isManagementKey: Bool = false
) -> OpenRouterKeyInfo {
    OpenRouterKeyInfo(
        label: "sk-or-v1-test...1234",
        limit: limit,
        limitRemaining: limitRemaining,
        limitReset: limitReset,
        usage: 80.5,
        usageDaily: 1.25,
        usageWeekly: 12.5,
        usageMonthly: 75,
        isManagementKey: isManagementKey
    )
}
