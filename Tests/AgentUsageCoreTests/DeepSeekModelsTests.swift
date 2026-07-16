import AgentUsageCore
import Foundation
import Testing

@Test func parsesDeepSeekBalanceResponse() throws {
    let json = """
    {
      "is_available": true,
      "balance_infos": [
        {
          "currency": "CNY",
          "total_balance": "42.50",
          "granted_balance": "2.50",
          "topped_up_balance": "40.00"
        }
      ]
    }
    """

    let data = try #require(json.data(using: .utf8))
    let response = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: data)

    #expect(response.isAvailable)
    #expect(response.balanceInfos.first?.currency == "CNY")
    #expect(response.balanceInfos.first?.totalBalance == "42.50")
}

@Test func createsOfficialDeepSeekSnapshot() throws {
    let response = DeepSeekBalanceResponse(
        isAvailable: true,
        balanceInfos: [
            DeepSeekBalanceInfo(
                currency: "USD",
                totalBalance: "10.00",
                grantedBalance: "1.00",
                toppedUpBalance: "9.00"
            )
        ]
    )

    let snapshot = DeepSeekSnapshotFactory.snapshot(from: response)

    #expect(snapshot.id == "deepseek")
    #expect(snapshot.health == .ready)
    #expect(snapshot.metrics.first?.confidence == .official)
    #expect(snapshot.metrics.first?.value == "10.00 USD")
}

@Test func createsDeepSeekSnapshotForMultipleKeys() throws {
    let availableResponse = DeepSeekBalanceResponse(
        isAvailable: true,
        balanceInfos: [
            DeepSeekBalanceInfo(
                currency: "USD",
                totalBalance: "12.00",
                grantedBalance: "2.00",
                toppedUpBalance: "10.00"
            )
        ]
    )
    let unavailableResponse = DeepSeekBalanceResponse(isAvailable: false, balanceInfos: [])
    let accounts = [
        DeepSeekBalanceAccount(
            id: "work",
            label: "Work",
            isDefault: true,
            response: availableResponse
        ),
        DeepSeekBalanceAccount(
            id: "test",
            label: "Test",
            response: unavailableResponse
        ),
        DeepSeekBalanceAccount(
            id: "broken",
            label: "Broken",
            response: nil,
            errorMessage: "HTTP 401"
        )
    ]

    let snapshot = DeepSeekSnapshotFactory.snapshot(from: accounts)

    #expect(snapshot.health == .ready)
    #expect(snapshot.headline == "1/3 DeepSeek key(s) available")
    #expect(snapshot.metrics.first { $0.id == "balance" }?.value == "12.00 USD")
    #expect(snapshot.metrics.first { $0.id == "api-keys" }?.value == "3")
    #expect(snapshot.metrics.first { $0.id == "available-keys" }?.value == "1/3")
    #expect(snapshot.notes.contains { $0.contains("usage-history") })
    #expect(snapshot.notes.contains { $0.contains("Broken") })
}

@Test func deepSeekSnapshotFormatsObservedTodayUsage() throws {
    let response = DeepSeekBalanceResponse(
        isAvailable: true,
        balanceInfos: [
            DeepSeekBalanceInfo(
                currency: "USD",
                totalBalance: "10.00",
                grantedBalance: "1.00",
                toppedUpBalance: "9.00"
            )
        ]
    )
    let usageSummary = UsageSummary(
        todayTokens: 18_200,
        thirtyDayTokens: 2_400_000,
        latestTokens: 1_100,
        topModel: "deepseek-chat"
    )

    let snapshot = DeepSeekSnapshotFactory.snapshot(from: response, usageSummary: usageSummary)

    #expect(snapshot.metrics.first { $0.id == "today-tokens" }?.value == "18.2K")
    #expect(snapshot.metrics.first { $0.id == "today-tokens" }?.confidence == .observed)
    #expect(snapshot.metrics.first { $0.id == "today-cost" }?.label == "Today cost")
    #expect(snapshot.metrics.first { $0.id == "30d-tokens" }?.value == "2.4M")
    #expect(snapshot.metrics.first { $0.id == "latest-tokens" }?.value == "1.1K")
}

@Test func deepSeekSnapshotKeepsUnverifiedCostUnavailable() throws {
    let response = DeepSeekBalanceResponse(
        isAvailable: true,
        balanceInfos: [
            DeepSeekBalanceInfo(
                currency: "USD",
                totalBalance: "10.00",
                grantedBalance: "1.00",
                toppedUpBalance: "9.00"
            )
        ]
    )
    let summary = UsageCostSummary(
        todayCost: nil,
        thirtyDayCost: nil,
        todayUnpricedEventCount: 1,
        thirtyDayUnpricedEventCount: 2
    )

    let snapshot = DeepSeekSnapshotFactory.snapshot(from: response, costSummary: summary)
    let todayCost = try #require(snapshot.metrics.first { $0.id == "today-cost" })
    let thirtyDayCost = try #require(snapshot.metrics.first { $0.id == "30d-cost" })

    #expect(todayCost.value == "Unavailable")
    #expect(todayCost.confidence == .unavailable)
    #expect(todayCost.detail.contains("1 response"))
    #expect(thirtyDayCost.value == "Unavailable")
    #expect(thirtyDayCost.confidence == .unavailable)
    #expect(thirtyDayCost.detail.contains("2 response"))
}

@Test func deepSeekSnapshotMapsObservedResponseUsageToExactCredentialAndModel() throws {
    let now = Date(timeIntervalSince1970: 1_704_067_200)
    let response = DeepSeekBalanceResponse(
        isAvailable: true,
        balanceInfos: [
            DeepSeekBalanceInfo(
                currency: "USD",
                totalBalance: "10.00",
                grantedBalance: "1.00",
                toppedUpBalance: "9.00"
            )
        ]
    )
    let accounts = [
        DeepSeekBalanceAccount(id: "work", label: "Work", isDefault: true, response: response),
        DeepSeekBalanceAccount(id: "lab", label: "Lab", response: response)
    ]
    let events = [
        UsageEvent(
            providerID: "deepseek",
            accountID: "work",
            model: "deepseek-chat",
            inputTokens: 100,
            outputTokens: 200,
            totalTokens: 300,
            createdAt: now,
            confidence: .observed
        ),
        UsageEvent(
            providerID: "deepseek",
            accountID: "lab",
            model: "deepseek-reasoner",
            inputTokens: 1_000,
            outputTokens: 2_000,
            totalTokens: 3_000,
            createdAt: now,
            confidence: .observed
        ),
        UsageEvent(
            providerID: "deepseek",
            model: "deepseek-chat",
            inputTokens: 10,
            outputTokens: 20,
            totalTokens: 30,
            createdAt: now,
            confidence: .observed
        )
    ]

    let snapshot = DeepSeekSnapshotFactory.snapshot(
        from: accounts,
        events: events,
        updatedAt: now
    )

    let work = try #require(snapshot.accounts?.first { $0.id == "work" })
    let lab = try #require(snapshot.accounts?.first { $0.id == "lab" })
    let unattributed = try #require(snapshot.accounts?.first { $0.id == "unattributed" })

    #expect(work.name == "Work")
    #expect(work.detail.contains("Local label"))
    #expect(work.metrics.first { $0.id == "balance" }?.confidence == .official)
    #expect(work.metrics.first { $0.id == "30d-tokens" }?.value == "300")
    #expect(work.activity?.reduce(0) { $0 + Int($1.value) } == 300)
    #expect(work.models.first?.model == "deepseek-chat")
    #expect(work.models.first?.totalTokens == 300)
    #expect(work.models.first?.spendUSD == nil)
    #expect(work.models.first?.confidence == .observed)

    #expect(lab.metrics.first { $0.id == "30d-tokens" }?.value == "3.0K")
    #expect(lab.models.first?.model == "deepseek-reasoner")
    #expect(unattributed.metrics.first { $0.id == "30d-tokens" }?.value == "30")
    #expect(unattributed.notes.first?.contains("does not assign") == true)
}
