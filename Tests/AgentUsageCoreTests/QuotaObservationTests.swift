import AgentUsageCore
import Foundation
import Testing

@Test func quotaObservationRoundTripsOnlyScalarHistoryFields() throws {
    let observation = QuotaObservation(
        providerID: "codex",
        accountScopeID: String(repeating: "a", count: 64),
        quotaID: "codex-weekly",
        remainingFraction: 0.42,
        capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
        resetAt: Date(timeIntervalSince1970: 1_700_604_800)
    )

    let data = try JSONEncoder().encode(observation)
    let decoded = try JSONDecoder().decode(QuotaObservation.self, from: data)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(decoded == observation)
    #expect(
        Set(object.keys) == Set([
            "providerID",
            "accountScopeID",
            "quotaID",
            "remainingFraction",
            "capturedAt",
            "resetAt"
        ])
    )
}
