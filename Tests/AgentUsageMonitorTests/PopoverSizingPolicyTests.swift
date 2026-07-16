import Testing
@testable import AgentUsageMonitor

@Test func popoverSizingKeepsSparsePagesComfortable() {
    let height = PopoverSizingPolicy.height(
        forMeasuredContentHeight: 180,
        availableScreenHeight: 900
    )

    #expect(height == 260)
}

@Test func popoverSizingUsesNaturalHeightWhenItFits() {
    let height = PopoverSizingPolicy.height(
        forMeasuredContentHeight: 514.2,
        availableScreenHeight: 900
    )

    #expect(height == 515)
}

@Test func popoverSizingCapsLongPagesAtPreferredMaximum() {
    let height = PopoverSizingPolicy.height(
        forMeasuredContentHeight: 920,
        availableScreenHeight: 1_000
    )

    #expect(height == 720)
}

@Test func popoverSizingRespectsSmallScreenAvailableHeight() {
    let height = PopoverSizingPolicy.height(
        forMeasuredContentHeight: 920,
        availableScreenHeight: 560
    )

    #expect(height == 528)
}

@Test func popoverSizingNeverExceedsAnExtremelySmallScreen() {
    let height = PopoverSizingPolicy.height(
        forMeasuredContentHeight: 300,
        availableScreenHeight: 220
    )

    #expect(height == 188)
}

@Test func popoverResizeAnimatesOnlyWhenVisibleAndMotionIsAllowed() {
    #expect(PopoverAnimationPolicy.shouldAnimateResize(
        requested: true,
        isPopoverShown: true,
        reduceMotion: false
    ))
    #expect(PopoverAnimationPolicy.shouldAnimateResize(
        requested: false,
        isPopoverShown: true,
        reduceMotion: false
    ) == false)
    #expect(PopoverAnimationPolicy.shouldAnimateResize(
        requested: true,
        isPopoverShown: false,
        reduceMotion: false
    ) == false)
    #expect(PopoverAnimationPolicy.shouldAnimateResize(
        requested: true,
        isPopoverShown: true,
        reduceMotion: true
    ) == false)
}

@Test func popoverBottomEdgeResizeUsesShortRestrainedDuration() {
    #expect(PopoverAnimationPolicy.resizeDuration > 0)
    #expect(PopoverAnimationPolicy.resizeDuration <= 0.25)
}
