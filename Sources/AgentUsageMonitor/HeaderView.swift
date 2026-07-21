import SwiftUI

struct HeaderView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        HStack(spacing: 6) {
            ForEach(viewModel.navigationItems) { item in
                Button {
                    guard viewModel.selectedProviderID != item.id else { return }
                    viewModel.selectedProviderID = item.id
                } label: {
                    BrandIcon(
                        icon: item.icon,
                        accessibilityLabel: item.title,
                        isSelected: viewModel.selectedProviderID == item.id
                    )
                        .frame(width: 35, height: 32)
                        // Transparent artwork should not create holes in the tab's hit target.
                        .contentShape(Rectangle())
                }
                .buttonStyle(TabButtonStyle(isSelected: viewModel.selectedProviderID == item.id))
                .help(item.title)
            }

            Button {
                Task {
                    await viewModel.refresh()
                }
            } label: {
                Image(systemName: viewModel.isRefreshing ? "arrow.triangle.2.circlepath.circle" : "arrow.clockwise")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 30, height: 32)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignSurface.muted)
            .background(DesignSurface.panel.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .help("Refresh")

            Button {
                viewModel.quitApplication()
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 30, height: 32)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignSurface.muted)
            .background(DesignSurface.panel.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .help("Quit Agent Usage Monitor")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}
