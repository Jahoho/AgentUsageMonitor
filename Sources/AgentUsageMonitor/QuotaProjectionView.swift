import AgentUsageCore
import Foundation
import SwiftUI

struct QuotaProjectionCard: View {
    let snapshot: ProviderSnapshot
    let projection: QuotaProjection?

    private var resolvedProjection: QuotaProjection {
        QuotaProjectionPresentation.resolvedProjection(
            snapshot: snapshot,
            projection: projection
        )
    }

    private var presentation: QuotaProjectionPresentation {
        QuotaProjectionPresentation(
            snapshot: snapshot,
            projection: resolvedProjection
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Quota projection")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignSurface.text)

                Spacer(minLength: 8)

                ConfidencePill(
                    text: resolvedProjection.confidence.rawValue,
                    confidence: resolvedProjection.confidence
                )
            }

            Text(presentation.primaryText)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(DesignSurface.text)
                .fixedSize(horizontal: false, vertical: true)

            if presentation.detailText.isEmpty == false {
                Text(presentation.detailText)
                    .font(.system(size: 9, weight: .regular))
                    .foregroundStyle(DesignSurface.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(11)
        .background(DesignSurface.panel.opacity(0.76))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct QuotaProjectionPresentation {
    let snapshot: ProviderSnapshot
    let projection: QuotaProjection

    var primaryText: String {
        guard projection.confidence == .estimated,
              let window = projection.constrainingWindow,
              let outcome = window.outcome
        else {
            return unavailableText
        }

        let label = Self.quotaLabel(window.quotaID, in: snapshot)
        switch outcome {
        case .remainingAtReset:
            return "\(label): \(Self.rangeText(for: window)) expected to remain at reset."
        case .mayExhaustBeforeReset:
            return "\(label) may run out before reset."
        case .likelyExhaustsBeforeReset:
            guard let exhaustionAt = window.projectedExhaustionAt,
                  window.forecastErrorFraction.map({
                      $0 <= QuotaWindowProjection.maximumPreciseForecastError
                  }) == true
            else {
                return "\(label) is expected to run out before reset."
            }
            return "\(label) is expected to run out around \(Self.dateText(exhaustionAt))."
        }
    }

    var detailText: String {
        if projection.confidence == .estimated,
           let window = projection.constrainingWindow {
            return "Based on \(Self.durationText(window.coverageDuration)) of recent Official history."
        }

        switch projection.availabilityReason {
        case .currentQuotaUnavailable:
            return "Previous history is not used without current Official quota."
        case .accountScopeUnavailable:
            return "The current account cannot be matched to its private local history."
        case .resetUnavailable:
            return "An Official reset time is required."
        case .historyUnavailable:
            return "Current Official quota remains unchanged."
        case .insufficientHistory, .sparseHistory, .unstableTrend, nil:
            return "Current Official quota remains the source of truth."
        }
    }

    static func resolvedProjection(
        snapshot: ProviderSnapshot,
        projection: QuotaProjection?
    ) -> QuotaProjection {
        if let projection, projection.providerID == snapshot.id {
            return projection
        }

        let reason: QuotaProjectionAvailabilityReason = snapshot.health == .ready
            ? .insufficientHistory
            : .currentQuotaUnavailable
        return .unavailable(
            providerID: snapshot.id,
            reason: reason,
            generatedAt: snapshot.updatedAt
        )
    }

    static func quotaLabel(_ quotaID: String, in snapshot: ProviderSnapshot) -> String {
        snapshot.bars.first { $0.id == quotaID }?.label ?? "Quota"
    }

    static func rangeText(for window: QuotaWindowProjection) -> String {
        guard let lowerBound = window.projectedRemainingLowerBound,
              let upperBound = window.projectedRemainingUpperBound
        else {
            return "Unavailable"
        }
        let lowerPercent = percentValue(lowerBound)
        let upperPercent = percentValue(upperBound)
        if lowerPercent == upperPercent {
            return "about \(lowerPercent)%"
        }
        return "\(lowerPercent)–\(upperPercent)%"
    }

    static func durationText(_ duration: TimeInterval) -> String {
        let totalMinutes = max(0, Int((duration / 60).rounded()))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0, minutes > 0 {
            return "\(hours)h \(minutes)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(minutes)m"
    }

    static func dateText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private var unavailableText: String {
        switch projection.availabilityReason {
        case .currentQuotaUnavailable:
            return "Current Official quota is unavailable."
        case .accountScopeUnavailable:
            return "Projection unavailable for the current account."
        case .resetUnavailable:
            return "Projection unavailable without a reset time."
        case .historyUnavailable:
            return "Local projection history is unavailable."
        case .insufficientHistory:
            return "Collecting more history before projecting."
        case .sparseHistory:
            return "Not enough continuous history for a reliable projection."
        case .unstableTrend:
            return "Recent usage varies too much for a reliable projection."
        case nil:
            return "Projection unavailable."
        }
    }

    private static func percentValue(_ fraction: Double) -> Int {
        Int((min(max(fraction, 0), 1) * 100).rounded())
    }
}
