import AgentUsageCore
import Foundation
import Testing

@Test func parsesCodexUsageBarsFromVisiblePageText() {
    let text = """
    Codex
    Updated just now

    Session
    5% used
    42% in reserve
    Resets in 2h 41m

    Weekly
    57% used
    25% in reserve
    Resets in 1d 6h
    """

    let snapshot = CodexUsageTextParser.snapshot(from: text)

    #expect(snapshot.health == .ready)
    #expect(snapshot.bars.count == 2)
    #expect(snapshot.bars.first { $0.id == "codex-session" }?.remainingFraction == 0.95)
    #expect(snapshot.bars.first { $0.id == "codex-session" }?.usedText == "95% left")
    #expect(snapshot.bars.first { $0.id == "codex-weekly" }?.resetText == "Resets in 1d 6h")
}

@Test func parsesCodexWebResetTextIntoAbsoluteResetDate() {
    let updatedAt = Date(timeIntervalSince1970: 1_704_067_200)
    let text = """
    Codex
    Updated just now

    Session
    5% used
    Resets in 2h 41m
    """

    let snapshot = CodexUsageTextParser.snapshot(from: text, updatedAt: updatedAt)

    #expect(snapshot.bars.first { $0.id == "codex-session" }?.resetAt == updatedAt.addingTimeInterval(9_660))
}

@Test func returnsSetupSnapshotWhenCodexTextHasNoUsageBars() {
    let snapshot = CodexUsageTextParser.snapshot(from: "Please sign in to continue")

    #expect(snapshot.health == .needsSetup)
    #expect(snapshot.bars.isEmpty)
}

@Test func parsesCodexUsageBarWithLongResetText() {
    let longResetDetail = String(repeating: "detail ", count: 40)
    let text = """
    Session
    8% used
    Resets in 12h 30m \(longResetDetail)

    Other content
    """

    let snapshot = CodexUsageTextParser.snapshot(from: text)

    #expect(snapshot.bars.first?.remainingFraction == 0.92)
    #expect(snapshot.bars.first?.resetText.hasPrefix("Resets in 12h 30m") == true)
}

@Test func parsesCodexResetBankFromOfficialPageTextWhenExpiryIsVisible() {
    let text = """
    Codex

    Session
    5% used
    Resets in 2h 41m

    Reset bank
    2 available
    Referral reset expires 2026-07-20
    Referral reset expires 2026-08-01
    """

    let snapshot = CodexUsageTextParser.snapshot(from: text)

    #expect(snapshot.quotaCreditBank?.availableCount(now: Date(timeIntervalSince1970: 1_782_892_800)) == 2)
    #expect(snapshot.quotaCreditBank?.entries.count == 2)
    #expect(snapshot.quotaCreditBank?.entries.first?.confidence == .official)
}

@Test func parsesCodexResetExpiryDatesFromOfficialPageMetadata() {
    let text = """
    Codex

    Session
    5% used
    Resets in 2h 41m

    Reset credits
    2 available

    [time] datetime: 2026-07-30 | aria-label: Reset credit expires July 30, 2026
    [div] title: Referral credit valid until 30 Aug 2026
    """

    let snapshot = CodexUsageTextParser.snapshot(from: text)

    #expect(snapshot.quotaCreditBank?.availableCount(now: Date(timeIntervalSince1970: 1_782_892_800)) == 2)
    #expect(snapshot.quotaCreditBank?.entries.count == 2)
    #expect(snapshot.quotaCreditBank?.entries.map(\.expiresAt).sorted().first == Date(timeIntervalSince1970: 1_785_455_999))
}

@Test func parsesCodexResetExpiryDatesFromChineseOfficialText() {
    let text = """
    Codex

    Session
    5% used
    Resets in 2h 41m

    Reset bank
    1 available
    Reset credit 到期 2026年7月30日
    """

    let snapshot = CodexUsageTextParser.snapshot(from: text)

    #expect(snapshot.quotaCreditBank?.availableCount(now: Date(timeIntervalSince1970: 1_782_892_800)) == 1)
    #expect(snapshot.quotaCreditBank?.entries.count == 1)
}

@Test func ignoresResetLikeTextWhenCodexUsageBarsAreMissing() {
    let text = """
    Reset bank
    2 available
    Referral reset expires 2026-07-20
    """

    let snapshot = CodexUsageTextParser.snapshot(from: text)

    #expect(snapshot.health == .needsSetup)
    #expect(snapshot.quotaCreditBank == nil)
}
