import Foundation

public struct CodexRateLimitWindow: Codable, Equatable, Sendable {
    public let usedPercent: Double
    public let windowMinutes: Int?
    public let resetsAt: Date?

    public init(usedPercent: Double, windowMinutes: Int?, resetsAt: Date?) {
        self.usedPercent = min(max(usedPercent, 0), 100)
        self.windowMinutes = windowMinutes
        self.resetsAt = resetsAt
    }
}

public struct CodexRateLimitSnapshot: Codable, Equatable, Sendable {
    public let primary: CodexRateLimitWindow?
    public let secondary: CodexRateLimitWindow?
    public let source: String
    public let email: String?
    public let plan: String?
    public let accountPlan: String?
    public let quotaPlan: String?
    public let limitName: String?
    public let resetBank: CodexResetBank?
    public let updatedAt: Date

    public init(
        primary: CodexRateLimitWindow?,
        secondary: CodexRateLimitWindow?,
        source: String,
        email: String? = nil,
        plan: String? = nil,
        accountPlan: String? = nil,
        quotaPlan: String? = nil,
        limitName: String? = nil,
        resetBank: CodexResetBank? = nil,
        updatedAt: Date = Date()
    ) {
        self.primary = primary
        self.secondary = secondary
        self.source = source
        self.email = email
        self.plan = plan
        self.accountPlan = accountPlan
        self.quotaPlan = quotaPlan
        self.limitName = limitName
        self.resetBank = resetBank
        self.updatedAt = updatedAt
    }
}

public enum CodexRateLimitSnapshotFactory {
    private static let sessionWindowMinutes = 300
    private static let weeklyWindowMinutes = 10_080

    public static func providerSnapshot(from snapshot: CodexRateLimitSnapshot) -> ProviderSnapshot {
        let bars = identifiedWindows(in: snapshot)
            .sorted { windowRank($0.id) < windowRank($1.id) }
            .map { identified in
                usageBar(
                    id: identified.id,
                    label: identified.label,
                    window: identified.window,
                    updatedAt: snapshot.updatedAt
                )
            }

        var metrics = [
            UsageMetric(
                id: "source",
                label: "Source",
                value: snapshot.source,
                detail: "Codex usage source",
                confidence: .official
            )
        ]

        if let email = snapshot.email {
            metrics.append(
                UsageMetric(
                    id: "account",
                    label: "Account",
                    value: email,
                    detail: friendlyPlanName(snapshot.accountPlan ?? snapshot.plan) ?? "ChatGPT subscription",
                    confidence: .official
                )
            )
        }

        if let quotaPlan = friendlyPlanName(snapshot.quotaPlan) {
            metrics.append(
                UsageMetric(
                    id: "quota-plan",
                    label: "Codex tier",
                    value: quotaPlan,
                    detail: snapshot.limitName ?? "Quota source: Codex rate limits",
                    confidence: .official
                )
            )
        } else if let plan = friendlyPlanName(snapshot.plan), snapshot.email == nil {
            metrics.append(
                UsageMetric(
                    id: "plan",
                    label: "Plan",
                    value: plan,
                    detail: "Codex account plan",
                    confidence: .official
                )
            )
        }

        if let resetBank = snapshot.resetBank {
            metrics.append(
                UsageMetric(
                    id: "codex-resets",
                    label: "Resets",
                    value: "\(resetBank.availableCount(now: snapshot.updatedAt))",
                    detail: resetBank.nextExpiry(now: snapshot.updatedAt)
                        .map { "Next expires \(resetDescription(from: $0.expiresAt))" }
                        ?? "Official reset count; expiry dates are shown only when the official source exposes them.",
                    confidence: .official
                )
            )
        }

        return ProviderSnapshot(
            id: "codex",
            name: "Codex",
            kind: .subscription,
            updatedAt: snapshot.updatedAt,
            health: bars.isEmpty ? .needsSetup : .ready,
            headline: bars.isEmpty ? "Codex account found, usage unavailable" : "Synced from \(snapshot.source)",
            metrics: metrics,
            bars: bars,
            quotaCreditBank: snapshot.resetBank,
            notes: [
                "Codex subscription windows are read from official local auth/RPC surfaces.",
                "Cached snapshots and local logs are not shown as Codex subscription usage."
            ],
            actions: []
        )
    }

    private static func usageBar(
        id: String,
        label: String,
        window: CodexRateLimitWindow,
        updatedAt: Date
    ) -> UsageBar {
        let remainingPercent = max(0, min(100, 100 - window.usedPercent))
        return UsageBar(
            id: id,
            label: label,
            remainingFraction: remainingPercent / 100,
            usedText: "\(Int(remainingPercent.rounded()))% left",
            resetText: window.resetsAt.map { UsageBar.resetDescription(from: $0, now: updatedAt) } ?? "Reset unknown",
            resetAt: window.resetsAt,
            confidence: .official
        )
    }

    /// Official sources can expose a weekly-only window as `primary`.
    /// Prefer the explicit duration and use source position only for older schemas.
    private static func identifiedWindows(
        in snapshot: CodexRateLimitSnapshot
    ) -> [(id: String, label: String, window: CodexRateLimitWindow)] {
        var identified: [(id: String, label: String, window: CodexRateLimitWindow)] = []

        if let primary = snapshot.primary {
            identified.append(identifiedWindow(primary, fallbackID: "codex-session", fallbackLabel: "Session"))
        }
        if let secondary = snapshot.secondary {
            identified.append(identifiedWindow(secondary, fallbackID: "codex-weekly", fallbackLabel: "Weekly"))
        }

        var seenIDs: Set<String> = []
        return identified.filter { seenIDs.insert($0.id).inserted }
    }

    private static func identifiedWindow(
        _ window: CodexRateLimitWindow,
        fallbackID: String,
        fallbackLabel: String
    ) -> (id: String, label: String, window: CodexRateLimitWindow) {
        switch window.windowMinutes {
        case sessionWindowMinutes:
            return ("codex-session", "Session", window)
        case weeklyWindowMinutes:
            return ("codex-weekly", "Weekly", window)
        default:
            return (fallbackID, fallbackLabel, window)
        }
    }

    private static func windowRank(_ id: String) -> Int {
        id == "codex-session" ? 0 : 1
    }

    private static func friendlyPlanName(_ plan: String?) -> String? {
        guard let plan = plan?.trimmingCharacters(in: .whitespacesAndNewlines), plan.isEmpty == false else {
            return nil
        }

        switch plan.lowercased() {
        case "free":
            return "ChatGPT Free"
        case "plus":
            return "ChatGPT Plus"
        case "pro":
            return "ChatGPT Pro"
        case "team":
            return "ChatGPT Team"
        case "enterprise":
            return "ChatGPT Enterprise"
        case "prolite":
            return "Codex Pro Lite"
        default:
            return plan
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .capitalized
        }
    }

    private static func resetDescription(from date: Date) -> String {
        UsageBar.resetDescription(from: date)
    }
}
