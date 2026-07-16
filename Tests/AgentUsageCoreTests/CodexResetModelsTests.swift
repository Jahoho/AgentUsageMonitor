import AgentUsageCore
import Foundation
import Testing

@Test func codexResetBankSummarizesOfficialAvailableResetsAndExpiry() {
    let now = Date(timeIntervalSince1970: 1_704_067_200)
    let bank = CodexResetBank(
        entries: [
            CodexResetEntry(
                id: "expiring",
                label: "Referral reset",
                grantedAt: now.addingTimeInterval(-10 * 86_400),
                expiresAt: now.addingTimeInterval(3 * 86_400),
                status: .available,
                source: "OAuth API",
                confidence: .official
            ),
            CodexResetEntry(
                id: "used",
                label: "Referral reset",
                grantedAt: now.addingTimeInterval(-5 * 86_400),
                expiresAt: now.addingTimeInterval(25 * 86_400),
                status: .used,
                source: "OAuth API",
                confidence: .official
            )
        ],
        source: "OAuth API",
        updatedAt: now
    )

    #expect(bank.availableCount(now: now) == 1)
    #expect(bank.nextExpiry(now: now)?.id == "expiring")
    #expect(bank.recommendation(now: now) == .useSoon)
}

@Test func codexResetParserExtractsOfficialBankedResetsWithoutRateLimitWindows() throws {
    let json = """
    {
      "rate_limit": {
        "primary": { "used_percent": 50, "reset_at": 1704074400 }
      },
      "reset_bank": {
        "resets": [
          {
            "id": "r_1",
            "label": "Referral reset",
            "granted_at": 1703203200,
            "expires_at": 1705795200,
            "status": "available"
          }
        ]
      }
    }
    """
    let data = try #require(json.data(using: .utf8))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

    let bank = try #require(CodexResetParser.resetBank(in: object, source: "OAuth API", updatedAt: Date(timeIntervalSince1970: 1_704_067_200)))

    #expect(bank.entries.count == 1)
    #expect(bank.entries[0].id == "r_1")
    #expect(bank.entries[0].expiresAt == Date(timeIntervalSince1970: 1_705_795_200))
    #expect(bank.entries[0].confidence == .official)
}

@Test func codexResetParserNormalizesMillisecondExpiryTimestamps() throws {
    let json = """
    {
      "reset_bank": {
        "resets": [
          {
            "id": "r_ms",
            "expires_at": 1705795200000,
            "status": "available"
          }
        ]
      }
    }
    """
    let data = try #require(json.data(using: .utf8))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

    let bank = try #require(CodexResetParser.resetBank(in: object, source: "OAuth API", updatedAt: Date(timeIntervalSince1970: 1_704_067_200)))

    #expect(bank.entries.first?.expiresAt == Date(timeIntervalSince1970: 1_705_795_200))
}

@Test func codexResetParserExtractsOfficialAvailableCountWhenExpiryIsNotExposed() throws {
    let json = """
    {
      "rateLimitResetCredits": {
        "availableCount": 3
      }
    }
    """
    let data = try #require(json.data(using: .utf8))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let now = Date(timeIntervalSince1970: 1_704_067_200)

    let bank = try #require(CodexResetParser.resetBank(in: object, source: "CLI RPC", updatedAt: now))

    #expect(bank.availableCount(now: now) == 3)
    #expect(bank.entries.isEmpty)
    #expect(bank.nextExpiry(now: now) == nil)
    #expect(bank.recommendation(now: now) == .hold)
}

@Test func codexResetParserExtractsOfficialRPCResetCreditExpiryDetails() throws {
    let json = """
    {
      "rateLimitResetCredits": {
        "availableCount": 2,
        "credits": [
          {
            "id": "RateLimitResetCredit_1",
            "resetType": "codexRateLimits",
            "status": "available",
            "grantedAt": 1897401600,
            "expiresAt": 1900000000,
            "title": "Full reset (Weekly + 5 hr)",
            "description": "Ready to redeem"
          },
          {
            "id": "RateLimitResetCredit_2",
            "resetType": "codexRateLimits",
            "status": "available",
            "grantedAt": 1897401600,
            "expiresAt": null,
            "title": null,
            "description": null
          }
        ]
      }
    }
    """
    let data = try #require(json.data(using: .utf8))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let now = Date(timeIntervalSince1970: 1_897_500_000)

    let bank = try #require(CodexResetParser.resetBank(in: object, source: "CLI RPC", updatedAt: now))

    #expect(bank.availableCount(now: now) == 2)
    #expect(bank.entries.count == 1)
    let entry = try #require(bank.entries.first)
    #expect(entry.id == "RateLimitResetCredit_1")
    #expect(entry.label == "Full reset (Weekly + 5 hr)")
    #expect(entry.grantedAt == Date(timeIntervalSince1970: 1_897_401_600))
    #expect(entry.expiresAt == Date(timeIntervalSince1970: 1_900_000_000))
    #expect(entry.status == .available)
}

@Test func codexResetParserExtractsOfficialWebAPIResetCreditExpiryDetails() throws {
    let json = """
    {
      "credits": [
        {
          "id": "RateLimitResetCredit_api",
          "reset_type": "codex_rate_limits",
          "status": "future_status",
          "granted_at": "2030-02-15T00:00:00Z",
          "expires_at": "2030-03-17T00:00:00.123Z",
          "title": "One free rate limit reset",
          "description": "Thanks for using Codex!"
        }
      ],
      "available_count": 3,
      "total_earned_count": 4
    }
    """
    let data = try #require(json.data(using: .utf8))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let now = Date(timeIntervalSince1970: 1_897_500_000)

    let bank = try #require(CodexResetParser.resetBank(in: object, source: "OAuth API", updatedAt: now))

    #expect(bank.availableCount(now: now) == 3)
    #expect(bank.entries.count == 1)
    let entry = try #require(bank.entries.first)
    #expect(entry.label == "One free rate limit reset")
    #expect(entry.status == .unknown)
    #expect(entry.grantedAt == ISO8601DateFormatter().date(from: "2030-02-15T00:00:00Z"))
    #expect(entry.expiresAt.timeIntervalSince1970 == 1_899_936_000.123)
}

@Test func codexResetBankPrefersOfficialReportedCountOverPartialExpiryEntries() {
    let now = Date(timeIntervalSince1970: 1_704_067_200)
    let bank = CodexResetBank(
        entries: [
            CodexResetEntry(
                id: "visible-expiry",
                label: "Referral reset",
                grantedAt: nil,
                expiresAt: now.addingTimeInterval(4 * 86_400),
                status: .available,
                source: "Codex web session",
                confidence: .official
            )
        ],
        reportedAvailableCount: 3,
        source: "Codex web session",
        updatedAt: now
    )

    #expect(bank.availableCount(now: now) == 3)
    #expect(bank.availableEntries(now: now).count == 1)
}
