import Foundation

public enum MenuBarStatusLevel: String, Codable, Equatable, Sendable {
    case ready
    case active
    case lowQuota
    case needsSetup
    case stale
    case error
    case unavailable
}

public struct MenuBarStatusSnapshot: Equatable, Sendable {
    public let providerID: String
    public let providerName: String
    public let level: MenuBarStatusLevel
    public let remainingFraction: Double?
    public let detail: String

    public init(
        providerID: String,
        providerName: String,
        level: MenuBarStatusLevel,
        remainingFraction: Double?,
        detail: String
    ) {
        self.providerID = providerID
        self.providerName = providerName
        self.level = level
        self.remainingFraction = remainingFraction.map { min(max($0, 0), 1) }
        self.detail = detail
    }

    public var accessibilityLabel: String {
        if let remainingFraction {
            let percent = Int((remainingFraction * 100).rounded())
            return "\(providerName) \(percent)% left, \(detail)"
        }

        return "\(providerName), \(detail)"
    }
}

public enum MenuBarStatusFactory {
    public static func snapshot(from snapshots: [ProviderSnapshot], now: Date = Date()) -> MenuBarStatusSnapshot {
        let providers = snapshots.filter { $0.id != "overview" }

        if let activeSnapshot = mostActiveProvider(in: providers, now: now, currentHourOnly: true) {
            return MenuBarStatusSnapshot(
                providerID: activeSnapshot.snapshot.id,
                providerName: activeSnapshot.snapshot.name,
                level: .active,
                remainingFraction: preferredMenuBarRemainingFraction(in: activeSnapshot.snapshot),
                detail: "Active now"
            )
        }

        if let lowQuotaSnapshot = lowestQuotaProvider(in: providers, threshold: 0.2) {
            return MenuBarStatusSnapshot(
                providerID: lowQuotaSnapshot.snapshot.id,
                providerName: lowQuotaSnapshot.snapshot.name,
                level: .lowQuota,
                remainingFraction: lowQuotaSnapshot.remainingFraction,
                detail: "\(Int((lowQuotaSnapshot.remainingFraction * 100).rounded()))% left"
            )
        }

        if let errorSnapshot = providers.first(where: { $0.health == .error }) {
            return MenuBarStatusSnapshot(
                providerID: errorSnapshot.id,
                providerName: errorSnapshot.name,
                level: .error,
                remainingFraction: preferredMenuBarRemainingFraction(in: errorSnapshot),
                detail: errorSnapshot.headline
            )
        }

        if let activeSnapshot = mostActiveProvider(in: providers, now: now, currentHourOnly: false) {
            return MenuBarStatusSnapshot(
                providerID: activeSnapshot.snapshot.id,
                providerName: activeSnapshot.snapshot.name,
                level: .active,
                remainingFraction: preferredMenuBarRemainingFraction(in: activeSnapshot.snapshot),
                detail: "Active today"
            )
        }

        if let readySnapshot = providers.first(where: { $0.health == .ready }) {
            return MenuBarStatusSnapshot(
                providerID: readySnapshot.id,
                providerName: readySnapshot.name,
                level: .ready,
                remainingFraction: preferredMenuBarRemainingFraction(in: readySnapshot),
                detail: readySnapshot.headline
            )
        }

        if let setupSnapshot = providers.first(where: { $0.health == .needsSetup }) {
            return MenuBarStatusSnapshot(
                providerID: setupSnapshot.id,
                providerName: setupSnapshot.name,
                level: .needsSetup,
                remainingFraction: nil,
                detail: setupSnapshot.headline
            )
        }

        return MenuBarStatusSnapshot(
            providerID: "monitor",
            providerName: "Agent Usage Monitor",
            level: .unavailable,
            remainingFraction: nil,
            detail: "No provider data"
        )
    }

    private static func lowestQuotaProvider(
        in snapshots: [ProviderSnapshot],
        threshold: Double
    ) -> (snapshot: ProviderSnapshot, remainingFraction: Double)? {
        snapshots
            .compactMap { snapshot -> (snapshot: ProviderSnapshot, remainingFraction: Double)? in
                guard let remainingFraction = preferredMenuBarRemainingFraction(in: snapshot),
                      remainingFraction <= threshold
                else {
                    return nil
                }

                return (snapshot, remainingFraction)
            }
            .min { $0.remainingFraction < $1.remainingFraction }
    }

    private static func mostActiveProvider(
        in snapshots: [ProviderSnapshot],
        now: Date,
        currentHourOnly: Bool,
        calendar: Calendar = .current
    ) -> (snapshot: ProviderSnapshot, activityValue: Double)? {
        let currentHourID = "hour-\(calendar.component(.hour, from: now))"

        return snapshots
            .filter { $0.health != .error }
            .compactMap { snapshot -> (snapshot: ProviderSnapshot, activityValue: Double)? in
                let total: Double
                if currentHourOnly {
                    total = snapshot.activity?.first { $0.id == currentHourID }?.value ?? 0
                } else {
                    total = snapshot.activity?.reduce(0) { $0 + $1.value } ?? 0
                }

                guard total > 0 else {
                    return nil
                }

                return (snapshot, total)
            }
            .max { $0.activityValue < $1.activityValue }
    }

    private static func lowestRemainingFraction(in snapshot: ProviderSnapshot) -> Double? {
        snapshot.bars
            .compactMap(\.remainingFraction)
            .min()
    }

    private static func preferredMenuBarRemainingFraction(in snapshot: ProviderSnapshot) -> Double? {
        if snapshot.id == "codex" {
            return snapshot.bars.first { $0.id == "codex-session" }?.remainingFraction
                ?? snapshot.bars.first { $0.label.caseInsensitiveCompare("Session") == .orderedSame }?.remainingFraction
                ?? snapshot.bars.first?.remainingFraction
        }

        return lowestRemainingFraction(in: snapshot)
    }
}
