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
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Weekly recap")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(DesignSurface.text)

                        if let periodText = presentation.periodText {
                            Text(periodText)
                                .font(.system(size: 8, weight: .regular))
                                .foregroundStyle(DesignSurface.muted)
                        }
                    }

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

                Text(presentation.summaryText)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(DesignSurface.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if isExpanded {
                    Divider()
                        .overlay(DesignSurface.track)
                        .padding(.vertical, 2)

                    if resolvedReview.completedCycle != nil {
                        ReviewDetailRow(label: "Rhythm", value: presentation.rhythmText)
                        ReviewDetailRow(label: "Capacity", value: presentation.capacityText)
                        ReviewDetailRow(label: "Compared", value: presentation.baselineText)
                        ReviewDetailRow(label: "Plan fit", value: presentation.planFitText)
                        ReviewDetailRow(label: "Data quality", value: presentation.dataQualityText)
                    } else {
                        ReviewDetailRow(label: "Status", value: presentation.summaryText)
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
        .help(isExpanded ? "Collapse weekly recap" : "Expand weekly recap")
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

    var periodText: String? {
        guard let cycle = review.completedCycle else {
            return nil
        }
        let finalDay = cycle.resetAt.addingTimeInterval(-1)
        return "\(Self.dateText(cycle.startedAt))–\(Self.dateText(finalDay))"
    }

    var primaryText: String {
        guard let cycle = review.completedCycle else {
            return unavailableText
        }
        if cycle.lowestRemainingFraction <= WeeklySubscriptionReviewAnalyzer.lowHeadroomThreshold {
            return "A near-limit week"
        }

        switch cycle.rhythm?.pattern {
        case .quiet:
            return "A light week"
        case .concentrated:
            return "A concentrated week"
        case .steady:
            return "A steady week"
        case .mixed:
            return "A varied week"
        case nil:
            return "Weekly recap ready"
        }
    }

    var summaryText: String {
        guard let cycle = review.completedCycle else {
            return unavailableDetailText
        }

        let remaining = Self.percentValue(cycle.endingRemainingFraction)
        guard let rhythm = cycle.rhythm else {
            return "\(remaining)% remained near reset; rhythm needs more continuous samples."
        }
        if rhythm.pattern == .quiet {
            return "Little Official quota change was observed; \(remaining)% remained near reset."
        }

        let dayCount = rhythm.activeDayCount
        let dayLabel = dayCount == 1 ? "day" : "days"
        if let peakDay = Self.weekdayName(rhythm.peakWeekday) {
            return "Observed use spanned \(dayCount) \(dayLabel), peaking \(peakDay); \(remaining)% remained near reset."
        }
        return "Observed use spanned \(dayCount) \(dayLabel); \(remaining)% remained near reset."
    }

    var rhythmText: String {
        guard let rhythm = review.completedCycle?.rhythm else {
            return "Not enough continuous samples to assign a rhythm."
        }
        if rhythm.pattern == .quiet {
            return "Little meaningful Official quota change was observed."
        }

        let peak = Self.weekdayName(rhythm.peakWeekday).map { " · largest drop \($0)" } ?? ""
        let dayLabel = rhythm.activeDayCount == 1 ? "day" : "days"
        switch rhythm.pattern {
        case .concentrated:
            return "Concentrated across \(rhythm.activeDayCount) \(dayLabel)\(peak)"
        case .steady:
            return "Spread across \(rhythm.activeDayCount) \(dayLabel)\(peak)"
        case .mixed:
            return "Observed across \(rhythm.activeDayCount) \(dayLabel)\(peak)"
        case .quiet:
            return "Little meaningful Official quota change was observed."
        }
    }

    var capacityText: String {
        guard let cycle = review.completedCycle else {
            return "Unavailable"
        }
        let remaining = Self.percentValue(cycle.endingRemainingFraction)
        let timing = cycle.endObservationLead < 60 * 60
            ? "near reset"
            : "\(Self.durationText(cycle.endObservationLead)) before reset"
        if cycle.lowestRemainingFraction <= WeeklySubscriptionReviewAnalyzer.lowHeadroomThreshold {
            return "Reached 5% headroom or less · \(remaining)% remained \(timing)"
        }
        return "\(remaining)% remained \(timing) · low-headroom zone not reached"
    }

    var baselineText: String {
        guard let comparison = review.baselineComparison else {
            let previousCount = max(0, review.eligibleCompletedCycleCount - 1)
            return "Needs 3 earlier complete cycles · \(previousCount) available"
        }

        let difference = comparison.usedDifferenceFraction
        let percentagePoints = Int((abs(difference) * 100).rounded())
        if percentagePoints < 5 {
            return "About typical vs your recent \(comparison.comparisonCycleCount)-cycle median"
        }
        if difference > 0 {
            return "\(percentagePoints) pp more quota used than your recent \(comparison.comparisonCycleCount)-cycle median"
        }
        return "\(percentagePoints) pp less quota used than your recent \(comparison.comparisonCycleCount)-cycle median"
    }

    var planFitText: String {
        guard let planFit = review.planFit else {
            return "Needs 3 complete cycles · \(review.eligibleCompletedCycleCount) available"
        }

        switch planFit.pattern {
        case .ampleHeadroom:
            return "Ample headroom in \(planFit.ampleHeadroomCycleCount) of \(planFit.evaluatedCycleCount) cycles"
        case .frequentPressure:
            return "Near the limit in \(planFit.nearLimitCycleCount) of \(planFit.evaluatedCycleCount) cycles"
        case .mixed:
            return "Mixed capacity outcomes across \(planFit.evaluatedCycleCount) cycles"
        }
    }

    var dataQualityText: String {
        guard let cycle = review.completedCycle else {
            return "Unavailable"
        }
        let coverage = Self.percentValue(cycle.sampleCoverageFraction)
        return "\(coverage)% of expected Official samples · final sample \(Self.durationText(cycle.endObservationLead)) before reset"
    }

    static func resolvedReview(
        snapshot: ProviderSnapshot,
        review: WeeklySubscriptionReview?
    ) -> WeeklySubscriptionReview {
        if let review, review.providerID == snapshot.id {
            return review
        }

        let weeklyResetAt = snapshot.bars.first {
            $0.id == WeeklySubscriptionReviewAnalyzer.weeklyQuotaID
        }?.resetAt
        let reason: WeeklySubscriptionReviewAvailabilityReason
        if snapshot.health != .ready {
            reason = .currentQuotaUnavailable
        } else if weeklyResetAt != nil {
            reason = .noCompletedCycle
        } else {
            reason = .weeklyWindowUnavailable
        }
        return .unavailable(
            providerID: snapshot.id,
            reason: reason,
            generatedAt: snapshot.updatedAt,
            currentResetAt: weeklyResetAt
        )
    }

    private var unavailableText: String {
        switch review.availabilityReason {
        case .currentQuotaUnavailable:
            return "Current Official weekly quota is unavailable."
        case .accountScopeUnavailable:
            return "Weekly recap is unavailable for the current account."
        case .weeklyWindowUnavailable:
            return "No Official weekly quota window is available."
        case .historyUnavailable:
            return "Local weekly recap history is unavailable."
        case .noCompletedCycle:
            return "First weekly recap is still being prepared."
        case .insufficientCompletedCycleCoverage, nil:
            return "The latest completed cycle could not be recapped reliably."
        }
    }

    private var unavailableDetailText: String {
        switch review.availabilityReason {
        case .currentQuotaUnavailable:
            return "Historical recap is not shown without current Official quota."
        case .accountScopeUnavailable:
            return "The current account cannot be matched to its private local history."
        case .weeklyWindowUnavailable:
            return "A seven-day Official window is required."
        case .historyUnavailable:
            return "Current Official quota remains unchanged."
        case .noCompletedCycle:
            return "It will appear after a fully observed weekly reset."
        case .insufficientCompletedCycleCoverage, nil:
            return "The cycle was not observed closely enough near its start, reset, or throughout the week."
        }
    }

    private static func percentValue(_ fraction: Double) -> Int {
        Int((min(max(fraction, 0), 1) * 100).rounded())
    }

    private static func weekdayName(_ weekday: Int?) -> String? {
        guard let weekday else {
            return nil
        }
        return [
            1: "Sun",
            2: "Mon",
            3: "Tue",
            4: "Wed",
            5: "Thu",
            6: "Fri",
            7: "Sat"
        ][weekday]
    }

    private static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        if duration < 60 * 60 {
            return "<1h"
        }
        let hours = max(1, Int((duration / 3_600).rounded()))
        return "\(hours)h"
    }
}
