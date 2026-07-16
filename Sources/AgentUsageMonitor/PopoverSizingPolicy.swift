import Foundation

enum PopoverSizingPolicy {
    static let width: CGFloat = 392
    static let initialHeight: CGFloat = 620
    static let minimumPreferredHeight: CGFloat = 260
    static let maximumPreferredHeight: CGFloat = 720
    static let screenMargin: CGFloat = 32

    static func height(
        forMeasuredContentHeight measuredContentHeight: CGFloat,
        availableScreenHeight: CGFloat
    ) -> CGFloat {
        let screenLimit = max(1, floor(availableScreenHeight - screenMargin))
        let maximumHeight = min(maximumPreferredHeight, screenLimit)
        let minimumHeight = min(minimumPreferredHeight, maximumHeight)
        let naturalHeight = ceil(max(0, measuredContentHeight))

        return min(max(naturalHeight, minimumHeight), maximumHeight)
    }
}

enum PopoverAnimationPolicy {
    static let resizeDuration: TimeInterval = 0.22

    static func shouldAnimateResize(
        requested: Bool,
        isPopoverShown: Bool,
        reduceMotion: Bool
    ) -> Bool {
        requested && isPopoverShown && reduceMotion == false
    }
}
