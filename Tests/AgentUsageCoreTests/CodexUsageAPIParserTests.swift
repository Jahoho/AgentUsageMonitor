import AgentUsageCore
import Foundation
import Testing

@Test func codexUsageAPIParserParsesSnakeCaseWindowsAndEmbeddedResetBank() throws {
    let updatedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let data = Data(
        """
        {
          "rate_limit": {
            "plan_type": "prolite",
            "primary_window": {
              "used_percent": 25,
              "limit_window_seconds": 18000,
              "reset_at": 1900000000
            }
          },
          "rate_limit_reset_credits": {
            "available_count": 1,
            "credits": [{
              "id": "reset-1",
              "status": "available",
              "expires_at": "2030-03-17T00:00:00Z"
            }]
          }
        }
        """.utf8
    )

    let snapshot = try CodexUsageAPIParser.parseSnapshot(
        from: data,
        email: "user@example.com",
        accountPlan: "pro",
        updatedAt: updatedAt
    )

    #expect(snapshot.primary?.usedPercent == 25)
    #expect(snapshot.primary?.windowMinutes == 300)
    #expect(snapshot.primary?.resetsAt == Date(timeIntervalSince1970: 1_900_000_000))
    #expect(snapshot.secondary == nil)
    #expect(snapshot.email == "user@example.com")
    #expect(snapshot.accountPlan == "pro")
    #expect(snapshot.quotaPlan == "prolite")
    #expect(snapshot.resetBank?.reportedAvailableCount == 1)
    #expect(snapshot.updatedAt == updatedAt)
}

@Test func codexUsageAPIParserParsesNestedCamelCaseAndMillisecondTimestamp() throws {
    let data = Data(
        """
        {
          "payload": [{
            "account": {
              "rateLimit": {
                "planType": " pro ",
                "primaryWindow": {
                  "usedPercent": "40.5",
                  "windowDurationMins": "300",
                  "resetAt": 1900000000000
                },
                "secondary": {
                  "used": 10,
                  "limitWindowSeconds": 604800
                }
              }
            }
          }]
        }
        """.utf8
    )

    let snapshot = try CodexUsageAPIParser.parseSnapshot(from: data)

    #expect(snapshot.primary?.usedPercent == 40.5)
    #expect(snapshot.primary?.windowMinutes == 300)
    #expect(snapshot.primary?.resetsAt == Date(timeIntervalSince1970: 1_900_000_000))
    #expect(snapshot.secondary?.usedPercent == 10)
    #expect(snapshot.secondary?.windowMinutes == 10_080)
    #expect(snapshot.quotaPlan == "pro")
}

@Test func codexUsageAPIParserRejectsMalformedOrWindowlessPayloads() {
    #expect(throws: CodexUsageAPIParsingError.invalidPayload) {
        try CodexUsageAPIParser.parseSnapshot(from: Data("not-json".utf8))
    }

    #expect(throws: CodexUsageAPIParsingError.missingRateLimit) {
        try CodexUsageAPIParser.parseSnapshot(
            from: Data(#"{"rate_limit":{"primary_window":{"reset_at":1900000000}}}"#.utf8)
        )
    }
}
