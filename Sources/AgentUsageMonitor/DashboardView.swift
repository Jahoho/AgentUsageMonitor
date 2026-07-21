import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.colorScheme) private var colorScheme

    let onMeasuredContentHeightChange: (CGFloat) -> Void

    private static let scrollTopID = "dashboard-scroll-top"

    init(
        viewModel: DashboardViewModel,
        onMeasuredContentHeightChange: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.onMeasuredContentHeightChange = onMeasuredContentHeightChange
    }

    var body: some View {
        ZStack {
            background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    HeaderView(viewModel: viewModel)
                    Divider()
                        .overlay(DesignSurface.track)
                        .opacity(0.65)
                }
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: PopoverHeightPreferenceKey.self,
                            value: [.chrome: proxy.size.height]
                        )
                    }
                }

                ScrollViewReader { scrollProxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        ZStack(alignment: .topLeading) {
                            selectedPage
                                .id(viewModel.selectedProviderID)
                                .background {
                                    GeometryReader { proxy in
                                        Color.clear.preference(
                                            key: PopoverHeightPreferenceKey.self,
                                            value: [
                                                .page(viewModel.selectedProviderID): proxy.size.height
                                            ]
                                        )
                                    }
                                }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .id(Self.scrollTopID)
                    }
                    .clipped()
                    .onChange(of: viewModel.selectedProviderID) { _, _ in
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            scrollProxy.scrollTo(Self.scrollTopID, anchor: .top)
                        }
                    }
                }
            }
        }
        .frame(width: PopoverSizingPolicy.width)
        .frame(maxHeight: .infinity, alignment: .top)
        .onPreferenceChange(PopoverHeightPreferenceKey.self) { measurements in
            guard let chromeHeight = measurements[.chrome],
                  let pageHeight = measurements[.page(viewModel.selectedProviderID)],
                  chromeHeight > 0,
                  pageHeight > 0
            else {
                return
            }

            onMeasuredContentHeightChange(chromeHeight + pageHeight)
        }
    }

    @ViewBuilder
    private var selectedPage: some View {
        if viewModel.selectedProviderID == "settings" {
            SettingsView(viewModel: viewModel)
        } else if viewModel.selectedProviderID == "overview", let snapshot = viewModel.selectedSnapshot {
            OverviewView(
                snapshot: snapshot,
                providerSnapshots: viewModel.snapshots.filter { $0.id != "overview" },
                weeklySubscriptionReviews: viewModel.weeklySubscriptionReviews
            )
        } else if let snapshot = viewModel.selectedSnapshot {
            ProviderSnapshotView(
                snapshot: snapshot,
                quotaProjection: viewModel.quotaProjections[snapshot.id],
                supportsQuotaProjection: viewModel.providerRegistrations
                    .first(where: { $0.id == snapshot.id })?
                    .supportsQuotaProjection == true,
                openAction: viewModel.open
            )
        } else {
            ContentUnavailableView("No providers", systemImage: "gauge.with.dots.needle.0percent")
                .padding(24)
        }
    }

    @ViewBuilder
    private var background: some View {
        if colorScheme == .dark {
            PopoverMaterialBackground()
                .overlay(DesignSurface.background)
        } else {
            DesignSurface.background
        }
    }
}

private enum PopoverMeasuredPart: Hashable {
    case chrome
    case page(String)
}

private struct PopoverHeightPreferenceKey: PreferenceKey {
    static let defaultValue: [PopoverMeasuredPart: CGFloat] = [:]

    static func reduce(
        value: inout [PopoverMeasuredPart: CGFloat],
        nextValue: () -> [PopoverMeasuredPart: CGFloat]
    ) {
        value.merge(nextValue()) { _, newValue in newValue }
    }
}
