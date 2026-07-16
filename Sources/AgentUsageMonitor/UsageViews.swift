import AgentUsageCore
import SwiftUI

struct MetricGrid: View {
    let metrics: [UsageMetric]

    private let columns = [
        GridItem(.flexible(minimum: 0), spacing: 12),
        GridItem(.flexible(minimum: 0), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(metrics) { metric in
                MetricTile(metric: metric)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MetricTile: View {
    let metric: UsageMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(metric.label)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(DesignSurface.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                ConfidenceDot(confidence: metric.confidence)
            }

            Text(metric.value)
                .font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(DesignSurface.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if let subvalue = metric.subvalue {
                Text(subvalue)
                    .font(.system(size: 10, weight: .regular, design: .rounded))
                    .foregroundStyle(DesignSurface.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .frame(maxWidth: .infinity, minHeight: metric.subvalue == nil ? 43 : 53, alignment: .topLeading)
        .help(metricHelpText)
    }

    private var metricHelpText: String {
        guard metric.detail.isEmpty == false else {
            return metric.confidence.rawValue
        }

        return "\(metric.confidence.rawValue): \(metric.detail)"
    }
}

struct UsageBarView: View {
    let bar: UsageBar

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(bar.label)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignSurface.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                Text(bar.displayResetText())
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(DesignSurface.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            MeterTrack(fraction: bar.remainingFraction, confidence: bar.confidence)

            HStack {
                Text(bar.usedText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(DesignSurface.text)
                    .lineLimit(1)
                Spacer()
                ConfidencePill(text: bar.confidence.rawValue, confidence: bar.confidence)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MeterTrack: View {
    let fraction: Double?
    let confidence: UsageConfidence

    private var clampedFraction: Double {
        min(max(fraction ?? 0, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DesignSurface.track)

                Capsule()
                    .fill(confidence == .unavailable ? DesignSurface.track.opacity(0.5) : DesignSurface.meter)
                    .frame(width: max(9, proxy.size.width * clampedFraction))

                ForEach([0.5, 0.8], id: \.self) { tick in
                    Rectangle()
                        .fill(DesignSurface.text.opacity(0.28))
                        .frame(width: 1, height: 8)
                        .offset(x: proxy.size.width * tick)
                }
            }
        }
        .frame(height: 7)
    }
}

struct ConfidencePill: View {
    let text: String
    let confidence: UsageConfidence

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.14))
            .clipShape(Capsule())
    }

    private var color: Color {
        switch confidence {
        case .official:
            return DesignSurface.official
        case .observed:
            return DesignSurface.accent
        case .estimated:
            return DesignSurface.activity
        case .unavailable:
            return DesignSurface.muted
        }
    }
}

struct ConfidenceDot: View {
    let confidence: UsageConfidence

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
    }

    private var color: Color {
        switch confidence {
        case .official:
            return DesignSurface.official
        case .observed:
            return DesignSurface.accent
        case .estimated:
            return DesignSurface.activity
        case .unavailable:
            return DesignSurface.muted.opacity(0.55)
        }
    }
}
