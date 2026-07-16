import AgentUsageCore
import Testing

@Test func formatsTokenCountsForCompactCards() {
    #expect(UsageValueFormatter.tokens(0) == "0")
    #expect(UsageValueFormatter.tokens(999) == "999")
    #expect(UsageValueFormatter.tokens(1_200) == "1.2K")
    #expect(UsageValueFormatter.tokens(18_000_000) == "18.0M")
    #expect(UsageValueFormatter.tokens(6_700_000_000) == "6.7B")
}
