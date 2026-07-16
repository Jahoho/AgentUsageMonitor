import AgentUsageCore
import AppKit

@MainActor
enum MenuBarStatusIconRenderer {
    static func image(for status: MenuBarStatusSnapshot) -> NSImage {
        let size = NSSize(width: 24, height: 18)
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        let ringRect = CGRect(x: 3.5, y: 1, width: 16, height: 16)
        drawRing(in: ringRect, status: status)
        drawProviderMark(providerID: status.providerID, in: CGRect(x: 7, y: 5, width: 9, height: 9))

        image.isTemplate = false
        image.accessibilityDescription = status.accessibilityLabel
        return image
    }

    private static func drawRing(in rect: CGRect, status: MenuBarStatusSnapshot) {
        let trackPath = NSBezierPath(ovalIn: rect)
        trackPath.lineWidth = 2.2
        NSColor.white.withAlphaComponent(0.22).setStroke()
        trackPath.stroke()

        let ringColor = color(for: status)
        guard let remainingFraction = status.remainingFraction else {
            ringColor.withAlphaComponent(0.85).setStroke()
            trackPath.stroke()
            return
        }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let endAngle = 90 - 360 * CGFloat(remainingFraction)
        let valuePath = NSBezierPath()
        valuePath.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 90,
            endAngle: endAngle,
            clockwise: true
        )
        valuePath.lineWidth = 2.4
        valuePath.lineCapStyle = .round
        ringColor.setStroke()
        valuePath.stroke()
    }

    private static func drawProviderMark(providerID: String, in rect: CGRect) {
        let backingPath = NSBezierPath(ovalIn: rect.insetBy(dx: -1.5, dy: -1.5))
        NSColor.black.withAlphaComponent(0.24).setFill()
        backingPath.fill()

        guard let logo = BrandLogoStore.shared.image(named: providerID),
              let context = NSGraphicsContext.current?.cgContext,
              let cgImage = logo.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            drawFallbackMark(providerID: providerID, in: rect)
            return
        }

        context.saveGState()
        context.clip(to: rect, mask: cgImage)
        NSColor.white.setFill()
        context.fill(rect)
        context.restoreGState()
    }

    private static func drawFallbackMark(providerID: String, in rect: CGRect) {
        let label = String(providerID.prefix(1)).uppercased()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 7.5, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let textSize = label.size(withAttributes: attributes)
        let textPoint = CGPoint(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2
        )
        label.draw(at: textPoint, withAttributes: attributes)
    }

    private static func color(for status: MenuBarStatusSnapshot) -> NSColor {
        if status.level == .error {
            return NSColor(srgbRed: 1.0, green: 0.34, blue: 0.28, alpha: 1)
        }

        if status.level == .active, status.remainingFraction == nil {
            return NSColor(srgbRed: 0.85, green: 0.58, blue: 0.30, alpha: 1)
        }

        guard let remainingFraction = status.remainingFraction else {
            return NSColor(srgbRed: 0.66, green: 0.65, blue: 0.61, alpha: 1)
        }

        switch remainingFraction {
        case ...0.2:
            return NSColor(srgbRed: 1.0, green: 0.42, blue: 0.32, alpha: 1)
        case ...0.5:
            return NSColor(srgbRed: 0.95, green: 0.66, blue: 0.26, alpha: 1)
        default:
            return NSColor(srgbRed: 0.25, green: 0.78, blue: 0.50, alpha: 1)
        }
    }
}
