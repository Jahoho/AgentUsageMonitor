import AgentUsageCore
import SwiftUI

struct ActivityStrip: View {
    let snapshot: ProviderSnapshot
    let buckets: [UsageActivityBucket]
    let title: String
    let summaryText: String
    let isReady: Bool

    @State private var hoveredBucketID: String?

    init(
        snapshot: ProviderSnapshot,
        buckets: [UsageActivityBucket],
        title: String? = nil,
        summaryText: String? = nil,
        isReady: Bool? = nil
    ) {
        self.snapshot = snapshot
        self.buckets = buckets
        self.title = title ?? "Today by hour"
        self.summaryText = summaryText
            ?? snapshot.metrics.first(where: { $0.id == "top-model" })?.value
            ?? snapshot.headline
        self.isReady = isReady ?? (snapshot.health == .ready)
    }

    private var maxValue: Double {
        max(1, buckets.map(\.value).max() ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(DesignSurface.muted)

                Spacer(minLength: 8)

                Text(summaryText)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(DesignSurface.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }

            GeometryReader { proxy in
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                        ActivityBucketColumn(
                            bucket: bucket,
                            maxValue: maxValue,
                            isReady: isReady,
                            isHovered: hoveredBucketID == bucket.id,
                            axisLabel: axisLabel(for: bucket, at: index)
                        )
                        .zIndex(hoveredBucketID == bucket.id ? 1 : 0)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        hoveredBucketID = bucketID(at: location.x, width: proxy.size.width)
                    case .ended:
                        hoveredBucketID = nil
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 76, maxHeight: 76, alignment: .bottom)
            .animation(.easeOut(duration: 0.12), value: hoveredBucketID)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bucketID(at xPosition: CGFloat, width: CGFloat) -> String? {
        guard buckets.isEmpty == false, width > 0 else {
            return nil
        }

        let bucketWidth = width / CGFloat(buckets.count)
        let rawIndex = Int((xPosition / bucketWidth).rounded(.down))
        let index = min(max(rawIndex, 0), buckets.count - 1)
        return buckets[index].id
    }

    private func axisLabel(for bucket: UsageActivityBucket, at index: Int) -> String? {
        if bucket.id == "hour-0"
            || bucket.id == "hour-6"
            || bucket.id == "hour-12"
            || bucket.id == "hour-18" {
            return String(bucket.label.prefix(2))
        }

        guard let axisLabel = bucket.axisLabel else {
            return nil
        }
        let isSpacedLabel = index == 0 || index == buckets.count - 1 || index.isMultiple(of: 7)
        return isSpacedLabel ? axisLabel : nil
    }
}

private struct ActivityBucketColumn: View {
    let bucket: UsageActivityBucket
    let maxValue: Double
    let isReady: Bool
    let isHovered: Bool
    let axisLabel: String?

    private var height: CGFloat {
        4 + (bucket.value / max(1, maxValue)) * 54
    }

    var body: some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(barColor)
                    .frame(width: isHovered ? 8.5 : 7, height: height)
                    .shadow(
                        color: DesignSurface.activity.opacity(isHovered ? 0.18 : 0),
                        radius: isHovered ? 3 : 0,
                        x: 0,
                        y: 1
                    )

                if isHovered {
                    ActivityHoverCard(bucket: bucket)
                        .offset(y: -height - 8)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .frame(height: 58, alignment: .bottom)
            .frame(maxWidth: .infinity, alignment: .bottom)
            .contentShape(Rectangle())
            .help("\(bucket.label): \(bucket.valueText) tokens")

            if let axisLabel {
                Text(axisLabel)
                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                    .foregroundStyle(DesignSurface.muted.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .frame(maxWidth: .infinity)
            } else {
                Color.clear
                    .frame(height: 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
    }

    private var barColor: Color {
        let readyOpacity = isHovered ? 1.0 : 0.82
        let unavailableOpacity = isHovered ? 0.55 : 0.35
        return DesignSurface.activity.opacity(isReady ? readyOpacity : unavailableOpacity)
    }
}

private struct ActivityHoverCard: View {
    let bucket: UsageActivityBucket

    var body: some View {
        VStack(spacing: 1) {
            Text(bucket.label)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
            Text(formattedValue)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(DesignSurface.text)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(DesignSurface.panel.opacity(0.96))
                .shadow(color: .black.opacity(0.10), radius: 7, x: 0, y: 3)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(DesignSurface.track.opacity(0.9), lineWidth: 0.8)
        )
        .fixedSize()
        .allowsHitTesting(false)
    }

    private var formattedValue: String {
        bucket.valueText
    }
}
