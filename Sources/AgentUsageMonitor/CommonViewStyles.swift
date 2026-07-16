import SwiftUI

struct TabButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 35, height: 32)
            .foregroundStyle(isSelected ? Color.white : DesignSurface.muted)
            .background(isSelected ? DesignSurface.accent : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(alignment: .bottom) {
                if isSelected {
                    Rectangle()
                        .fill(Color.white.opacity(0.95))
                        .frame(width: 20, height: 2)
                        .offset(y: 6)
                }
            }
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

struct ActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .foregroundStyle(DesignSurface.text)
            .background(DesignSurface.panel.opacity(configuration.isPressed ? 0.55 : 0.9))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
