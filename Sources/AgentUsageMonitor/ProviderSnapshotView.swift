import AgentUsageCore
import SwiftUI

struct ProviderSnapshotView: View {
    let snapshot: ProviderSnapshot
    let openAction: (ProviderAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            SnapshotTitle(snapshot: snapshot)

            if snapshot.bars.isEmpty == false {
                VStack(spacing: 11) {
                    ForEach(snapshot.bars) { bar in
                        UsageBarView(bar: bar)
                    }
                }
            }

            if snapshot.id == "codex", let resetBank = snapshot.quotaCreditBank {
                ResetBankView(bank: resetBank)
            }

            if snapshot.metrics.isEmpty == false {
                MetricGrid(metrics: visibleMetrics(for: snapshot))
            }

            if let activity = snapshot.activity, shouldShowActivityStrip(for: snapshot, activity: activity) {
                ActivityStrip(snapshot: snapshot, buckets: activity)
            }

            if let accounts = snapshot.accounts, accounts.isEmpty == false {
                ProviderAccountDetailsView(snapshot: snapshot, accounts: accounts)
                    .id(snapshot.id)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func visibleMetrics(for snapshot: ProviderSnapshot) -> [UsageMetric] {
        switch snapshot.id {
        case "codex":
            return snapshot.metrics.filter { ["today-tokens", "30d-tokens", "latest-tokens", "top-model"].contains($0.id) }
        case "deepseek":
            return snapshot.metrics.filter { ["balance", "today-tokens", "today-cost", "30d-tokens"].contains($0.id) }
        case "openrouter":
            return snapshot.metrics.filter {
                ["credit-balance", "today-cost", "month-cost", "all-time-cost"].contains($0.id)
            }
        case "overview":
            return snapshot.metrics
        default:
            return snapshot.metrics.prefix(2).map(\.self)
        }
    }

    private func shouldShowActivityStrip(for snapshot: ProviderSnapshot, activity: [UsageActivityBucket]) -> Bool {
        guard activity.isEmpty == false else {
            return false
        }

        if snapshot.id == "codex" {
            return true
        }

        return activity.contains { $0.value > 0 }
    }
}

private struct ProviderAccountDetailsView: View {
    let snapshot: ProviderSnapshot
    let accounts: [ProviderAccountSnapshot]

    @State private var selectedAccountID: String?

    private var selectedAccount: ProviderAccountSnapshot {
        accounts.first { $0.id == selectedAccountID }
            ?? accounts.first { $0.isDefault && $0.health == .ready }
            ?? accounts.first { $0.health == .ready }
            ?? accounts[0]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Divider()
                .overlay(DesignSurface.track)

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("API key details")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(DesignSurface.text)

                    if accounts.count == 1 {
                        Text(selectedAccount.name)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(DesignSurface.muted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if accounts.count > 1 {
                    Picker("API key", selection: accountSelection) {
                        ForEach(accounts) { account in
                            Text(account.name)
                                .tag(account.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(minWidth: 128, maxWidth: 210, alignment: .trailing)
                }

                ConfidencePill(
                    text: selectedAccount.health.rawValue,
                    confidence: confidence(for: selectedAccount.health)
                )
            }

            if selectedAccount.detail.isEmpty == false {
                Text(selectedAccount.detail)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(DesignSurface.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if selectedAccount.bars.isEmpty == false {
                VStack(spacing: 11) {
                    ForEach(selectedAccount.bars) { bar in
                        UsageBarView(bar: bar)
                    }
                }
            }

            let metrics = visibleAccountMetrics(selectedAccount)
            if metrics.isEmpty == false {
                MetricGrid(metrics: metrics)
            }

            if let activity = selectedAccount.activity, activity.isEmpty == false {
                ActivityStrip(
                    snapshot: snapshot,
                    buckets: activity,
                    title: selectedAccount.activityTitle,
                    summaryText: activitySummary(for: selectedAccount),
                    isReady: selectedAccount.health == .ready
                )
            }

            if selectedAccount.models.isEmpty == false {
                ProviderModelList(models: selectedAccount.models)
            }

            if selectedAccount.notes.isEmpty == false {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(selectedAccount.notes.enumerated()), id: \.offset) { _, note in
                        Text(note)
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(DesignSurface.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: reconcileSelection)
        .onChange(of: accounts.map(\.id)) { _, _ in
            reconcileSelection()
        }
    }

    private var accountSelection: Binding<String> {
        Binding(
            get: { selectedAccount.id },
            set: { selectedAccountID = $0 }
        )
    }

    private func reconcileSelection() {
        guard let selectedAccountID, accounts.contains(where: { $0.id == selectedAccountID }) else {
            self.selectedAccountID = accounts.first { $0.isDefault && $0.health == .ready }?.id
                ?? accounts.first { $0.health == .ready }?.id
                ?? accounts.first?.id
            return
        }
    }

    private func visibleAccountMetrics(_ account: ProviderAccountSnapshot) -> [UsageMetric] {
        let preferredIDs: [String]
        switch snapshot.id {
        case "openrouter":
            preferredIDs = [
                "today-cost", "week-cost", "month-cost", "all-time-cost",
                "key-limit", "key-remaining", "byok-month-cost"
            ]
        case "deepseek":
            preferredIDs = ["balance", "today-tokens", "30d-tokens", "30d-requests", "top-model"]
        default:
            preferredIDs = account.metrics.map(\.id)
        }

        return preferredIDs.compactMap { id in
            account.metrics.first { $0.id == id }
        }
    }

    private func activitySummary(for account: ProviderAccountSnapshot) -> String {
        account.metrics.first { $0.id == "top-model" }?.value
            ?? account.models.first?.model
            ?? "No model activity"
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

private struct ProviderModelList: View {
    let models: [UsageModelSummary]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Models")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(DesignSurface.muted)
                .padding(.bottom, 4)

            ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                ProviderModelRow(model: model)
                    .padding(.vertical, 7)

                if index < models.count - 1 {
                    Divider()
                        .overlay(DesignSurface.track.opacity(0.8))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ProviderModelRow: View {
    let model: UsageModelSummary

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(model.model)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(DesignSurface.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    ConfidenceDot(confidence: model.confidence)
                }

                if model.providerNames.isEmpty == false || model.latestAt != nil {
                    Text(modelDetail)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(DesignSurface.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Text(tokenBreakdown)
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(DesignSurface.muted.opacity(0.9))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(UsageValueFormatter.tokens(model.totalTokens))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignSurface.text)
                Text("\(model.requestCount) requests")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(DesignSurface.muted)
                if let spendUSD = model.spendUSD {
                    Text(formatUSD(spendUSD))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(DesignSurface.official)
                }
            }
            .frame(minWidth: 72, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var modelDetail: String {
        var parts: [String] = []
        if model.providerNames.isEmpty == false {
            parts.append(model.providerNames.joined(separator: ", "))
        }
        if let latestAt = model.latestAt {
            parts.append(latestAt.formatted(date: .abbreviated, time: .omitted))
        }
        return parts.joined(separator: " | ")
    }

    private var tokenBreakdown: String {
        var parts = [
            "In \(UsageValueFormatter.tokens(model.inputTokens))",
            "Out \(UsageValueFormatter.tokens(model.outputTokens))"
        ]
        if model.reasoningTokens > 0 {
            parts.append("Reasoning \(UsageValueFormatter.tokens(model.reasoningTokens))")
        }
        return parts.joined(separator: " | ")
    }

    private func formatUSD(_ value: Double) -> String {
        if value == 0 {
            return "$0.00"
        }
        if abs(value) < 0.01 {
            return String(format: "$%.4f", value)
        }
        return String(format: "$%.2f", value)
    }
}

struct SnapshotTitle: View {
    let snapshot: ProviderSnapshot

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.name)
                        .font(.system(size: 19, weight: .medium, design: .rounded))
                        .foregroundStyle(DesignSurface.text)
                    Text("Updated \(relativeUpdateText(snapshot.updatedAt))")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(DesignSurface.muted)
                }

                Spacer()

                ConfidencePill(text: snapshot.health.rawValue, confidence: confidenceForHealth(snapshot.health))
            }

            Divider()
                .overlay(DesignSurface.track)
        }
    }

    private func relativeUpdateText(_ date: Date) -> String {
        if abs(date.timeIntervalSinceNow) < 60 {
            return "just now"
        }

        return date.formatted(date: .omitted, time: .shortened)
    }

    private func confidenceForHealth(_ health: ProviderHealth) -> UsageConfidence {
        switch health {
        case .ready:
            return .observed
        case .needsSetup, .unavailable, .error:
            return .unavailable
        }
    }
}
