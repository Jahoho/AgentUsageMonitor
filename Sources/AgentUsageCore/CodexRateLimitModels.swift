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
    public static func providerSnapshot(from snapshot: CodexRateLimitSnapshot) -> ProviderSnapshot {
        var bars: [UsageBar] = []

        if let primary = snapshot.primary {
            bars.append(usageBar(id: "codex-session", label: "Session", window: primary, updatedAt: snapshot.updatedAt))
        }

        if let secondary = snapshot.secondary {
            bars.append(usageBar(id: "codex-weekly", label: "Weekly", window: secondary, updatedAt: snapshot.updatedAt))
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
