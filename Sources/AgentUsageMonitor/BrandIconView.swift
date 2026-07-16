import AppKit
import SwiftUI

struct BrandIcon: View {
    let icon: ProviderNavigationIcon
    let accessibilityLabel: String
    let isSelected: Bool

    init(icon: ProviderNavigationIcon, accessibilityLabel: String, isSelected: Bool) {
        self.icon = icon
        self.accessibilityLabel = accessibilityLabel
        self.isSelected = isSelected
    }

    init(providerID: String, isSelected: Bool) {
        let registration = ProviderRegistry.registration(for: providerID)
        self.icon = registration?.navigation.icon ?? .brand(resourceName: providerID)
        self.accessibilityLabel = registration?.navigation.title ?? providerID
        self.isSelected = isSelected
    }

    var body: some View {
        ZStack {
            switch icon {
            case .overview:
                OverviewMark(isSelected: isSelected)
            case .brand(let resourceName):
                BrandLogo(resourceName: resourceName, isSelected: isSelected)
            case .system(let symbolName):
                Image(systemName: symbolName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : DesignSurface.muted)
            }
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct BrandLogo: View {
    let resourceName: String
    let isSelected: Bool

    var body: some View {
        if let image = BrandLogoStore.shared.image(named: resourceName) {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(isSelected ? Color.white : DesignSurface.logo)
                .padding(5)
                .opacity(isSelected ? 1 : 0.9)
        } else {
            Circle()
                .fill(isSelected ? Color.white : DesignSurface.muted)
                .frame(width: 16, height: 16)
        }
    }
}

private struct OverviewMark: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(markColor.opacity(isSelected ? 0.55 : 0.38), lineWidth: 1.4)
                .frame(width: 22, height: 22)

            Circle()
                .fill(markColor)
                .frame(width: 6.5, height: 6.5)
                .offset(y: -7)

            Circle()
                .fill(markColor.opacity(isSelected ? 0.9 : 0.82))
                .frame(width: 5.5, height: 5.5)
                .offset(x: -7, y: 5.5)

            Circle()
                .fill(markColor.opacity(isSelected ? 0.9 : 0.82))
                .frame(width: 5.5, height: 5.5)
                .offset(x: 7, y: 5.5)

            Circle()
                .fill(markColor.opacity(isSelected ? 0.92 : 0.7))
                .frame(width: 3.5, height: 3.5)
        }
    }

    private var markColor: Color {
        isSelected ? Color.white : DesignSurface.logo
    }
}
