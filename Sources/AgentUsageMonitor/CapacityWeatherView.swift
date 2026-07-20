import AgentUsageCore
import Foundation
import SwiftUI

struct CompactCapacityWeatherView: View {
    let snapshot: ProviderSnapshot
    let insight: CapacityInsight?

    private var resolvedInsight: CapacityInsight {
        CapacityWeatherPresentation.resolvedInsight(snapshot: snapshot, insight: insight)
    }

    private var presentation: CapacityWeatherPresentation {
        CapacityWeatherPresentation(snapshot: snapshot, insight: resolvedInsight)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            CapacityWeatherIcon(weather: resolvedInsight.weather, size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("Capacity weather · \(presentation.weatherName)")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignSurface.text)

                Text(presentation.compactSummary)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(DesignSurface.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 6)

            ConfidencePill(
                text: resolvedInsight.confidence.rawValue,
                confidence: resolvedInsight.confidence
            )
        }
        .padding(11)
        .background(DesignSurface.panel.opacity(0.76))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct CapacityWeatherCard: View {
    let snapshot: ProviderSnapshot
    let insight: CapacityInsight?

    private var resolvedInsight: CapacityInsight {
        CapacityWeatherPresentation.resolvedInsight(snapshot: snapshot, insight: insight)
    }

    private var presentation: CapacityWeatherPresentation {
        CapacityWeatherPresentation(snapshot: snapshot, insight: resolvedInsight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .center, spacing: 10) {
                CapacityWeatherIcon(weather: resolvedInsight.weather, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Capacity weather")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(DesignSurface.muted)
                    Text(presentation.title)
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(DesignSurface.text)
                }

                Spacer(minLength: 8)

                ConfidencePill(
                    text: resolvedInsight.confidence.rawValue,
                    confidence: resolvedInsight.confidence
                )
            }

            Text(presentation.summary)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(DesignSurface.text)
                .fixedSize(horizontal: false, vertical: true)

            if resolvedInsight.windows.isEmpty == false {
                Divider()
                    .overlay(DesignSurface.track)

                VStack(spacing: 7) {
                    ForEach(resolvedInsight.windows) { window in
                        CapacityWindowRow(snapshot: snapshot, window: window)
                    }
                }
            }

            Text(presentation.sourceNote)
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(DesignSurface.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(DesignSurface.panel.opacity(0.76))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct CapacityWeatherIcon: View {
    let weather: CapacityWeather
    let size: CGFloat

    var body: some View {
        Image(systemName: weather.systemImage)
            .font(.system(size: size * 0.45, weight: .medium))
            .foregroundStyle(weather.displayColor)
            .frame(width: size, height: size)
            .background(weather.displayColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
            .accessibilityHidden(true)
    }
}

private struct CapacityWindowRow: View {
    let snapshot: ProviderSnapshot
    let window: HeadroomWindowInsight

    private var label: String {
        CapacityWeatherPresentation.quotaLabel(window.quotaID, in: snapshot)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignSurface.text)
                Spacer(minLength: 8)
                Text(window.weather.displayName)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(window.weather.displayColor)
            }

            Text(projectionText)
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(DesignSurface.text)
                .fixedSize(horizontal: false, vertical: true)

            Text(coverageText)
                .font(.system(size: 9, weight: .regular, design: .rounded))
                .foregroundStyle(DesignSurface.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .background(DesignSurface.track.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var projectionText: String {
        switch window.weather {
        case .storm:
            if let exhaustionAt = window.projectedExhaustionAt {
                return "May run out around \(CapacityWeatherPresentation.dateText(exhaustionAt)), before reset."
            }
            return "May run out before this window resets."
        case .clear, .windy:
            guard let projected = window.projectedRemainingAtReset else {
                return "Projection unavailable."
            }
            return "About \(CapacityWeatherPresentation.percentText(projected)) left at reset."
        case .learning:
            return "Not enough recent coverage for a forecast yet."
        case .fog:
            return "Current official data is unavailable."
        }
    }

    private var coverageText: String {
        var parts = [
            "\(window.sampleCount) samples over \(CapacityWeatherPresentation.durationText(window.coverageDuration))",
            "\(CapacityWeatherPresentation.percentText(window.sampleCoverageFraction)) coverage"
        ]
        if let consumptionPerHour = window.consumptionPerHour {
            parts.insert("\(CapacityWeatherPresentation.paceText(consumptionPerHour)) recent burn", at: 0)
        }
        return parts.joined(separator: " · ")
    }
}

struct CapacityWeatherPresentation {
    let snapshot: ProviderSnapshot
    let insight: CapacityInsight

    var weatherName: String {
        insight.weather.displayName
    }

    var title: String {
        switch insight.weather {
        case .clear:
            return "Clear headroom"
        case .windy:
            return "Headroom narrowing"
        case .storm:
            return "Capacity storm"
        case .fog:
            return "Forecast unavailable"
        case .learning:
            return "Learning your pace"
        }
    }

    var compactSummary: String {
        switch insight.weather {
        case .clear:
            return projectedResetSummary(prefix: "On pace for")
        case .windy:
            return projectedResetSummary(prefix: "Tight forecast for")
        case .storm:
            return exhaustionSummary(compact: true)
        case .fog, .learning:
            return unavailableSummary
        }
    }

    var summary: String {
        switch insight.weather {
        case .clear:
            return projectedResetSummary(prefix: "At the recent pace,")
        case .windy:
            return projectedResetSummary(prefix: "At the recent pace,")
        case .storm:
            return exhaustionSummary(compact: false)
        case .fog, .learning:
            return unavailableSummary
        }
    }

    var sourceNote: String {
        switch insight.confidence {
        case .estimated:
            return "Estimated locally from recent Official quota samples. Current Official data remains the source of truth."
        case .unavailable:
            return "No forecast is substituted for missing current Official data."
        case .official, .observed:
            return "Current Official data remains the source of truth."
        }
    }

    static func resolvedInsight(
        snapshot: ProviderSnapshot,
        insight: CapacityInsight?
    ) -> CapacityInsight {
        if let insight, insight.providerID == snapshot.id {
            return insight
        }

        let reason: HeadroomAvailabilityReason = snapshot.health == .ready
            ? .insufficientHistory
            : .currentQuotaUnavailable
        return .unavailable(
            providerID: snapshot.id,
            reason: reason,
            generatedAt: snapshot.updatedAt
        )
    }

    static func quotaLabel(_ quotaID: String, in snapshot: ProviderSnapshot) -> String {
        snapshot.bars.first { $0.id == quotaID }?.label ?? "Quota window"
    }

    static func percentText(_ fraction: Double) -> String {
        "\(Int((min(max(fraction, 0), 1) * 100).rounded()))%"
    }

    static func paceText(_ fractionPerHour: Double) -> String {
        let percentPerHour = max(0, fractionPerHour) * 100
        if percentPerHour > 0, percentPerHour < 0.1 {
            return "<0.1%/h"
        }
        return String(format: "%.1f%%/h", percentPerHour)
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

    private var constrainingWindow: HeadroomWindowInsight? {
        guard let quotaID = insight.constrainingQuotaID else {
            return insight.windows.first
        }
        return insight.windows.first { $0.quotaID == quotaID }
    }

    private var unavailableSummary: String {
        switch insight.availabilityReason {
        case .currentQuotaUnavailable:
            return "Current Official quota is unavailable. Previous history is not used as a substitute."
        case .accountScopeUnavailable:
            return "The Official account identity is unavailable, so local history cannot be matched privately."
        case .resetUnavailable:
            return "The Official quota has no reset time, so headroom cannot be forecast."
        case .historyUnavailable:
            return "Local quota history could not be read. Current Official quota remains unchanged."
        case .insufficientHistory, nil:
            return "Keep the app running while you work. More Official samples are needed for a forecast."
        }
    }

    private func projectedResetSummary(prefix: String) -> String {
        guard let window = constrainingWindow,
              let projected = window.projectedRemainingAtReset
        else {
            return "More Official samples are needed for a forecast."
        }
        let label = Self.quotaLabel(window.quotaID, in: snapshot)
        if prefix.hasSuffix(",") {
            let qualifier = insight.weather == .windy ? "only " : ""
            return "\(prefix) \(label) should reach reset with \(qualifier)\(Self.percentText(projected)) left."
        }
        return "\(prefix) \(label): \(Self.percentText(projected)) left at reset."
    }

    private func exhaustionSummary(compact: Bool) -> String {
        guard let window = constrainingWindow else {
            return "Recent pace may exhaust capacity before reset."
        }
        let label = Self.quotaLabel(window.quotaID, in: snapshot)
        if let exhaustionAt = window.projectedExhaustionAt {
            let timing = Self.dateText(exhaustionAt)
            return compact
                ? "\(label) may run out around \(timing)."
                : "At the recent pace, \(label) may run out around \(timing), before its reset."
        }
        return compact
            ? "\(label) may run out before reset."
            : "At the recent pace, \(label) may run out before its reset."
    }
}

private extension CapacityWeather {
    var displayName: String {
        switch self {
        case .clear:
            return "Clear"
        case .windy:
            return "Windy"
        case .storm:
            return "Storm"
        case .fog:
            return "Fog"
        case .learning:
            return "Learning"
        }
    }

    var systemImage: String {
        switch self {
        case .clear:
            return "sun.max.fill"
        case .windy:
            return "wind"
        case .storm:
            return "cloud.bolt.rain.fill"
        case .fog:
            return "cloud.fog.fill"
        case .learning:
            return "hourglass"
        }
    }

    var displayColor: Color {
        switch self {
        case .clear:
            return DesignSurface.official
        case .windy:
            return DesignSurface.activity
        case .storm:
            return DesignSurface.risk
        case .fog:
            return DesignSurface.muted
        case .learning:
            return DesignSurface.accent
        }
    }
}
