import AgentUsageCore
import Foundation
import Testing

@Test func mapsCodexRateLimitSnapshotToProviderSnapshot() {
    let now = Date()
    let rateLimits = CodexRateLimitSnapshot(
        primary: CodexRateLimitWindow(
            usedPercent: 12.4,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval(3_600)
        ),
        secondary: CodexRateLimitWindow(
            usedPercent: 57.1,
            windowMinutes: 10_080,
            resetsAt: now.addingTimeInterval(86_400)
        ),
        source: "CLI RPC",
        email: "person@example.com",
        plan: "pro",
        updatedAt: now
    )

    let snapshot = CodexRateLimitSnapshotFactory.providerSnapshot(from: rateLimits)

    #expect(snapshot.id == "codex")
    #expect(snapshot.health == .ready)
    #expect(snapshot.headline == "Synced from CLI RPC")
    #expect(snapshot.bars.count == 2)
    #expect(snapshot.bars.first { $0.id == "codex-session" }?.usedText == "88% left")
    #expect(snapshot.metrics.first { $0.id == "source" }?.value == "CLI RPC")
}

@Test func codexRateLimitWindowClampsUsedPercentToValidRange() {
    #expect(CodexRateLimitWindow(usedPercent: -10, windowMinutes: nil, resetsAt: nil).usedPercent == 0)
    #expect(CodexRateLimitWindow(usedPercent: 125, windowMinutes: nil, resetsAt: nil).usedPercent == 100)
}

@Test func codexRateLimitFactoryUsesOfficialDurationForWeeklyOnlyPrimaryWindow() {
    let now = Date(timeIntervalSince1970: 1_704_067_200)
    let rateLimits = CodexRateLimitSnapshot(
        primary: CodexRateLimitWindow(
            usedPercent: 40,
            windowMinutes: 10_080,
            resetsAt: now.addingTimeInterval(604_800)
        ),
        secondary: nil,
        source: "OAuth API",
        updatedAt: now
    )

    let snapshot = CodexRateLimitSnapshotFactory.providerSnapshot(from: rateLimits)

    #expect(snapshot.bars.map(\.id) == ["codex-weekly"])
    #expect(snapshot.bars.first?.label == "Weekly")
}

@Test func codexRateLimitSnapshotFormatsResetTimeFromSnapshotUpdateTime() {
    let updatedAt = Date(timeIntervalSince1970: 1_704_067_200)
    let resetsAt = updatedAt.addingTimeInterval(3_600)
    let rateLimits = CodexRateLimitSnapshot(
        primary: CodexRateLimitWindow(
            usedPercent: 10,
            windowMinutes: 300,
            resetsAt: resetsAt
        ),
        secondary: nil,
        source: "CLI RPC",
        updatedAt: updatedAt
    )

    let snapshot = CodexRateLimitSnapshotFactory.providerSnapshot(from: rateLimits)
    let session = snapshot.bars.first { $0.id == "codex-session" }

    #expect(session?.resetText == "Resets in 1h 0m")
    #expect(session?.resetAt == resetsAt)
}

@Test func mapsCodexResetBankToProviderSnapshot() {
    let now = Date(timeIntervalSince1970: 1_704_067_200)
    let resetBank = CodexResetBank(
        entries: [],
        reportedAvailableCount: 2,
        source: "CLI RPC",
        updatedAt: now
    )
    let rateLimits = CodexRateLimitSnapshot(
        primary: CodexRateLimitWindow(
            usedPercent: 10,
            windowMinutes: 300,
            resetsAt: now.addingTimeInterval(3_600)
        ),
        secondary: nil,
        source: "CLI RPC",
        resetBank: resetBank,
        updatedAt: now
    )

    let snapshot = CodexRateLimitSnapshotFactory.providerSnapshot(from: rateLimits)

    #expect(snapshot.quotaCreditBank == resetBank)
    #expect(snapshot.metrics.first { $0.id == "codex-resets" }?.value == "2")
    #expect(snapshot.metrics.first { $0.id == "codex-resets" }?.confidence == .official)
}
