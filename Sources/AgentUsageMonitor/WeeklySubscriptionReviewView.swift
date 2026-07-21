import AgentUsageCore
import Foundation
import SwiftUI

struct WeeklySubscriptionReviewCard: View {
    let snapshot: ProviderSnapshot
    let review: WeeklySubscriptionReview?

    @State private var isExpanded = false

    private var resolvedReview: WeeklySubscriptionReview {
        WeeklySubscriptionReviewPresentation.resolvedReview(
            snapshot: snapshot,
            review: review
        )
    }

    private var presentation: WeeklySubscriptionReviewPresentation {
        WeeklySubscriptionReviewPresentation(review: resolvedReview)
    }

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Weekly review")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(DesignSurface.text)

                    Spacer(minLength: 8)

                    ConfidencePill(
                        text: resolvedReview.confidence.rawValue,
                        confidence: resolvedReview.confidence
                    )

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DesignSurface.muted)
                }

                Text(presentation.primaryText)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignSurface.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text(presentation.compactComparisonText)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(DesignSurface.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if isExpanded {
                    Divider()
                        .overlay(DesignSurface.track)
                        .padding(.vertical, 2)

                    if resolvedReview.currentCycle != nil {
                        ReviewDetailRow(label: "Cycle coverage", value: presentation.coverageText)
                        ReviewDetailRow(label: "Sampling", value: presentation.samplingText)
                        ReviewDetailRow(label: "Previous cycle", value: presentation.expandedComparisonText)
                    } else {
                        ReviewDetailRow(label: "Status", value: presentation.compactComparisonText)
                    }
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignSurface.panel.opacity(0.76))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Collapse weekly review" : "Expand weekly review")
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}

private struct ReviewDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DesignSurface.muted)
                .frame(width: 82, alignment: .leading)

            Text(value)
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(DesignSurface.text)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}

struct WeeklySubscriptionReviewPresentation {
    let review: WeeklySubscriptionReview

    var primaryText: String {
        guard let cycle = review.currentCycle else {
            return unavailableText
        }

        let used = Self.percentValue(cycle.observedUsedFraction)
        switch cycle.usageScope {
        case .cycleToDate:
            return "\(used)% used so far this cycle."
        case .observedSpan:
            return "\(used)% used during the observed part of this cycle."
        }
    }

    var compactComparisonText: String {
        guard review.currentCycle != nil else {
            return unavailableDetailText
        }
        guard review.comparison != nil else {
            return "Building a fair same-point comparison with the previous cycle."
        }
        return comparisonText
    }

    var coverageText: String {
        guard let cycle = review.currentCycle else {
            return "Unavailable"
        }
        let duration = Self.durationText(cycle.coverageDuration)
        guard let cycleCoverage = cycle.cycleCoverageFraction else {
            return "\(duration) observed span"
        }
        return "\(Self.percentValue(cycleCoverage))% of cycle · \(duration)"
    }

    var samplingText: String {
        guard let cycle = review.currentCycle else {
            return "Unavailable"
        }
        return "\(Self.percentValue(cycle.sampleCoverageFraction))% of expected samples · \(cycle.sampleCount) saved"
    }

    var expandedComparisonText: String {
        guard review.comparison != nil else {
            switch review.comparisonAvailabilityReason {
            case .noPreviousCycle:
                return "No earlier observed weekly cycle yet."
            case .insufficientPreviousCoverage:
                return "The previous cycle was not observed from near its start."
            case .noComparablePoint:
                return "No previous sample is close enough to this point in the cycle."
            case nil:
                return "Still collecting comparable history."
            }
        }
        return comparisonText
    }

    static func resolvedReview(
        snapshot: ProviderSnapshot,
        review: WeeklySubscriptionReview?
    ) -> WeeklySubscriptionReview {
        if let review, review.providerID == snapshot.id {
            return review
        }

        let reason: WeeklySubscriptionReviewAvailabilityReason
        if snapshot.health != .ready {
            reason = .currentQuotaUnavailable
        } else if snapshot.bars.contains(where: { $0.id == WeeklySubscriptionReviewAnalyzer.weeklyQuotaID }) {
            reason = .insufficientCurrentCycle
        } else {
            reason = .weeklyWindowUnavailable
        }
        return .unavailable(
            providerID: snapshot.id,
            reason: reason,
            generatedAt: snapshot.updatedAt
        )
    }

    private var comparisonText: String {
        guard let comparison = review.comparison else {
            return "Previous-cycle comparison unavailable."
        }

        let difference = comparison.remainingDifferenceFraction
        let percentagePoints = Int((abs(difference) * 100).rounded())
        if percentagePoints < 2 {
            return "About the same remaining as last cycle at this point."
        }
        if difference > 0 {
            return "\(percentagePoints) pp more remaining than last cycle at this point."
        }
        return "\(percentagePoints) pp less remaining than last cycle at this point."
    }

    private var unavailableText: String {
        switch review.availabilityReason {
        case .currentQuotaUnavailable:
            return "Current Official weekly quota is unavailable."
        case .accountScopeUnavailable:
            return "Weekly review is unavailable for the current account."
        case .weeklyWindowUnavailable:
            return "No Official weekly quota window is available."
        case .historyUnavailable:
            return "Local weekly review history is unavailable."
        case .insufficientCurrentCycle, nil:
            return "Collecting this weekly cycle."
        }
    }

    private var unavailableDetailText: String {
        switch review.availabilityReason {
        case .currentQuotaUnavailable:
            return "Previous history is not shown without current Official quota."
        case .accountScopeUnavailable:
            return "The current account cannot be matched to its private local history."
        case .weeklyWindowUnavailable:
            return "A seven-day Official window is required."
        case .historyUnavailable:
            return "Current Official quota remains unchanged."
        case .insufficientCurrentCycle, nil:
            return "At least 30 minutes of current-cycle history is required."
        }
    }

    private static func percentValue(_ fraction: Double) -> Int {
        Int((min(max(fraction, 0), 1) * 100).rounded())
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let totalHours = max(0, Int((duration / 3_600).rounded()))
        let days = totalHours / 24
        let hours = totalHours % 24
        if days > 0, hours > 0 {
            return "\(days)d \(hours)h"
        }
        if days > 0 {
            return "\(days)d"
        }
        if totalHours > 0 {
            return "\(totalHours)h"
        }
        return "<1h"
    }
}
