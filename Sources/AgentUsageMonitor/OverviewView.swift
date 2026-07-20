import AgentUsageCore
import Foundation
import SwiftUI

struct OverviewView: View {
    let snapshot: ProviderSnapshot
    let providerSnapshots: [ProviderSnapshot]
    let capacityInsights: [String: CapacityInsight]

    private var activeAgent: OverviewActiveAgent? {
        OverviewActiveAgent.resolve(from: providerSnapshots)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SnapshotTitle(snapshot: snapshot)

            ActiveAgentPanel(agent: activeAgent)

            if let codexSnapshot = providerSnapshots.first(where: { $0.id == "codex" }) {
                CompactCapacityWeatherView(
                    snapshot: codexSnapshot,
                    insight: capacityInsights[codexSnapshot.id]
                )
            }

            OverviewActivityPanel(snapshot: snapshot)

            ProviderSourcesPanel(providers: providerSnapshots)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct ActiveAgentPanel: View {
    let agent: OverviewActiveAgent?

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            SectionHeader(title: "Active agent", subtitle: agent?.modeText ?? "Waiting")

            if let agent {
                HStack(alignment: .center, spacing: 12) {
                    BrandIcon(providerID: agent.snapshot.id, isSelected: false)
                        .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(agent.snapshot.name)
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .foregroundStyle(DesignSurface.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        Text(agent.snapshot.headline)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(DesignSurface.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(agent.primaryValue)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(DesignSurface.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(agent.primaryLabel)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(DesignSurface.muted)
                    }
                }

                HStack(spacing: 7) {
                    CompactStat(label: "Now", value: agent.currentHourText)
                    CompactStat(label: "Today", value: agent.todayText)
                    CompactStat(label: "Reset", value: agent.resetText)
                }
            } else {
                EmptyOverviewState(
                    systemName: "gauge.with.dots.needle.0percent",
                    title: "No connected provider",
                    detail: "Add provider credentials or sign in from Settings."
                )
            }
        }
        .overviewPanelStyle()
    }
}

private struct OverviewActivityPanel: View {
    let snapshot: ProviderSnapshot

    private var activity: [UsageActivityBucket] {
        snapshot.activity ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Today activity", subtitle: "All providers")

            if activity.contains(where: { $0.value > 0 }) {
                ActivityStrip(snapshot: snapshot, buckets: activity)
            } else {
                EmptyOverviewState(
                    systemName: "chart.bar.xaxis",
                    title: "No observed tokens today",
                    detail: "Codex logs and DeepSeek proxy events will appear here after refresh."
                )
            }
        }
        .overviewPanelStyle()
    }
}

private struct ProviderSourcesPanel: View {
    let providers: [ProviderSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Sources", subtitle: "Provider status")

            VStack(spacing: 7) {
                ForEach(providers) { provider in
                    ProviderSourceRow(snapshot: provider)
                }
            }
        }
        .overviewPanelStyle()
    }
}

private struct ProviderSourceRow: View {
    let snapshot: ProviderSnapshot

    private var quotaText: String? {
        guard let quota = OverviewActiveAgent.preferredQuota(in: snapshot),
              let remainingFraction = quota.remainingFraction
        else {
            return nil
        }

        return "\(Int((remainingFraction * 100).rounded()))% left"
    }

    var body: some View {
        HStack(spacing: 9) {
            BrandIcon(providerID: snapshot.id, isSelected: false)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.name)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignSurface.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(snapshot.headline)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(DesignSurface.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 4) {
                ConfidencePill(text: snapshot.health.rawValue, confidence: confidence(for: snapshot.health))

                if let quotaText {
                    Text(quotaText)
                        .font(.system(size: 10, weight: .regular, design: .rounded))
                        .foregroundStyle(DesignSurface.muted)
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(DesignSurface.track.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func confidence(for health: ProviderHealth) -> UsageConfidence {
        switch health {
        case .ready:
            return .observed
        case .needsSetup, .unavailable, .error:
            return .unavailable
        }
    }
}

private struct CompactStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(DesignSurface.muted)
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(DesignSurface.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(DesignSurface.track.opacity(0.32))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct EmptyOverviewState: View {
    let systemName: String
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            IconTile(systemName: systemName)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignSurface.text)
                Text(detail)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(DesignSurface.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct OverviewActiveAgent {
    let snapshot: ProviderSnapshot
    let modeText: String
    let currentHourTokens: Int
    let todayTokens: Int
    let quota: UsageBar?

    var primaryValue: String {
        if let remainingFraction = quota?.remainingFraction {
            return "\(Int((remainingFraction * 100).rounded()))%"
        }

        return todayText
    }

    var primaryLabel: String {
        quota?.remainingFraction == nil ? "today" : "left"
    }

    var currentHourText: String {
        UsageValueFormatter.tokens(currentHourTokens)
    }

    var todayText: String {
        UsageValueFormatter.tokens(todayTokens)
    }

    var resetText: String {
        quota?.displayResetText() ?? statusText
    }

    private var statusText: String {
        switch snapshot.health {
        case .ready:
            return "Ready"
        case .needsSetup:
            return "Setup"
        case .unavailable:
            return "Unavailable"
        case .error:
            return "Error"
        }
    }

    static func resolve(
        from snapshots: [ProviderSnapshot],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> OverviewActiveAgent? {
        let currentHourID = "hour-\(calendar.component(.hour, from: now))"
        let nonErrorSnapshots = snapshots.filter { $0.health != .error }

        if let current = nonErrorSnapshots
            .compactMap({ candidate(from: $0, currentHourID: currentHourID, modeText: "Active now") })
            .filter({ $0.currentHourTokens > 0 })
            .max(by: { $0.currentHourTokens < $1.currentHourTokens }) {
            return current
        }

        if let today = nonErrorSnapshots
            .compactMap({ candidate(from: $0, currentHourID: currentHourID, modeText: "Active today") })
            .filter({ $0.todayTokens > 0 })
            .max(by: { $0.todayTokens < $1.todayTokens }) {
            return today
        }

        if let ready = snapshots.first(where: { $0.health == .ready }) {
            return candidate(from: ready, currentHourID: currentHourID, modeText: "Ready")
        }

        if let first = snapshots.first {
            return candidate(from: first, currentHourID: currentHourID, modeText: first.health.rawValue)
        }

        return nil
    }

    static func preferredQuota(in snapshot: ProviderSnapshot) -> UsageBar? {
        if snapshot.id == "codex" {
            return snapshot.bars.first { $0.id == "codex-session" }
                ?? snapshot.bars.first { $0.label.caseInsensitiveCompare("Session") == .orderedSame }
                ?? snapshot.bars.first
        }

        return snapshot.bars
            .filter { $0.remainingFraction != nil }
            .min { ($0.remainingFraction ?? 1) < ($1.remainingFraction ?? 1) }
    }

    private static func candidate(
        from snapshot: ProviderSnapshot,
        currentHourID: String,
        modeText: String
    ) -> OverviewActiveAgent {
        let activity = snapshot.activity ?? []
        let currentHourTokens = Int((activity.first { $0.id == currentHourID }?.value ?? 0).rounded())
        let todayTokens = Int(activity.reduce(0) { $0 + $1.value }.rounded())

        return OverviewActiveAgent(
            snapshot: snapshot,
            modeText: modeText,
            currentHourTokens: currentHourTokens,
            todayTokens: todayTokens,
            quota: preferredQuota(in: snapshot)
        )
    }
}

private struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(DesignSurface.text)
            Spacer()
            Text(subtitle)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(DesignSurface.muted)
        }
    }
}

private struct IconTile: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(DesignSurface.activity)
            .frame(width: 31, height: 31)
            .background(DesignSurface.track.opacity(0.42))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private extension View {
    func overviewPanelStyle() -> some View {
        padding(12)
            .background(DesignSurface.panel.opacity(0.76))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
