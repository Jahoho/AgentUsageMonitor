import AppKit
import SwiftUI

enum DesignSurface {
    static let background = dynamicColor(
        light: NSColor(red: 0.975, green: 0.965, blue: 0.945, alpha: 1),
        dark: NSColor(red: 0.235, green: 0.240, blue: 0.250, alpha: 0.46)
    )
    static let panel = dynamicColor(
        light: NSColor(red: 1.000, green: 0.992, blue: 0.975, alpha: 1),
        dark: NSColor.white.withAlphaComponent(0.13)
    )
    static let track = dynamicColor(
        light: NSColor(red: 0.910, green: 0.900, blue: 0.875, alpha: 1),
        dark: NSColor.white.withAlphaComponent(0.16)
    )
    static let text = dynamicColor(
        light: NSColor(red: 0.160, green: 0.150, blue: 0.135, alpha: 1),
        dark: NSColor.white.withAlphaComponent(0.94)
    )
    static let muted = dynamicColor(
        light: NSColor(red: 0.500, green: 0.475, blue: 0.430, alpha: 1),
        dark: NSColor.white.withAlphaComponent(0.70)
    )
    static let logo = dynamicColor(
        light: NSColor(red: 0.205, green: 0.190, blue: 0.165, alpha: 1),
        dark: NSColor.white.withAlphaComponent(0.82)
    )
    static let accent = dynamicColor(
        light: NSColor(red: 0.105, green: 0.400, blue: 0.780, alpha: 1),
        dark: NSColor(red: 0.280, green: 0.640, blue: 1.000, alpha: 1)
    )
    static let official = dynamicColor(
        light: NSColor(red: 0.230, green: 0.560, blue: 0.390, alpha: 1),
        dark: NSColor(red: 0.400, green: 0.780, blue: 0.600, alpha: 1)
    )
    static let meter = dynamicColor(
        light: NSColor(red: 0.690, green: 0.455, blue: 0.255, alpha: 1),
        dark: NSColor(red: 0.360, green: 0.700, blue: 1.000, alpha: 1)
    )
    static let activity = dynamicColor(
        light: NSColor(red: 0.780, green: 0.560, blue: 0.335, alpha: 1),
        dark: NSColor(red: 0.570, green: 0.780, blue: 1.000, alpha: 1)
    )

    private static func dynamicColor(light: NSColor, dark: NSColor) -> Color {
        Color(NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [.darkAqua, .aqua])
            return match == .darkAqua ? dark : light
        })
    }
}
