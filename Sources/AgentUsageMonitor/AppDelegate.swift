import AgentUsageCore
import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    private var backgroundRefreshTask: Task<Void, Never>?
    private var popoverResizeTask: Task<Void, Never>?
    private var outsideClickMonitor: Any?
    private let popover = NSPopover()
    private let viewModel = DashboardViewModel()
    private var measuredPopoverContentHeight = PopoverSizingPolicy.initialHeight
    private var targetPopoverHeight = PopoverSizingPolicy.initialHeight

    func applicationDidFinishLaunching(_ notification: Notification) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.target = self
        self.statusItem = statusItem
        bindStatusItem()

        popover.behavior = .transient
        popover.delegate = self
        popover.animates = false
        popover.contentSize = NSSize(
            width: PopoverSizingPolicy.width,
            height: PopoverSizingPolicy.initialHeight
        )
        let hostingController = NSHostingController(
            rootView: DashboardView(
                viewModel: viewModel,
                onMeasuredContentHeightChange: { [weak self] measuredHeight in
                    Task { @MainActor [weak self] in
                        self?.schedulePopoverHeightUpdate(for: measuredHeight)
                    }
                }
            )
        )
        hostingController.sizingOptions = []
        popover.contentViewController = hostingController
        BrandLogoStore.shared.preload(
            viewModel.navigationItems.compactMap { $0.icon.brandResourceName }
        )
        viewModel.startLocalServices()

        Task {
            await viewModel.refresh()
        }

        startBackgroundRefreshLoop()
    }

    func applicationWillTerminate(_ notification: Notification) {
        backgroundRefreshTask?.cancel()
        popoverResizeTask?.cancel()
        stopOutsideClickMonitoring()
    }

    func popoverDidShow(_ notification: Notification) {
        startOutsideClickMonitoring()
    }

    func popoverDidClose(_ notification: Notification) {
        stopOutsideClickMonitoring()
    }

    private func bindStatusItem() {
        viewModel.$menuBarStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                self?.updateStatusItem(status)
            }
            .store(in: &cancellables)
    }

    private func startBackgroundRefreshLoop() {
        backgroundRefreshTask = Task { [weak self] in
            while Task.isCancelled == false {
                try? await Task.sleep(for: .seconds(60))
                await self?.viewModel.refreshIfStale(maxAge: 45)
            }
        }
    }

    private func updateStatusItem(_ status: MenuBarStatusSnapshot) {
        guard let button = statusItem?.button else { return }

        button.image = MenuBarStatusIconRenderer.image(for: status)
        button.image?.isTemplate = false
        button.toolTip = status.accessibilityLabel
        button.setAccessibilityLabel(status.accessibilityLabel)
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }

        if popover.isShown {
            closePopover()
        } else {
            applyPopoverSize(animateResize: false)
            popover.animates = false
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            applyPopoverSize(animateResize: false)
            makePopoverWindowTranslucent()
            NSApplication.shared.activate(ignoringOtherApps: true)
            Task {
                await viewModel.refreshIfStale()
            }
        }
    }

    private func closePopover() {
        guard popover.isShown else {
            return
        }

        popover.animates = false
        popover.performClose(nil)
    }

    private func startOutsideClickMonitoring() {
        guard outsideClickMonitor == nil else {
            return
        }

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closePopover()
            }
        }
    }

    private func stopOutsideClickMonitoring() {
        guard let outsideClickMonitor else {
            return
        }

        NSEvent.removeMonitor(outsideClickMonitor)
        self.outsideClickMonitor = nil
    }

    private func updatePopoverHeight(for measuredHeight: CGFloat) {
        guard measuredHeight.isFinite, measuredHeight > 0 else {
            return
        }

        measuredPopoverContentHeight = measuredHeight
        guard popover.isShown else {
            return
        }
        applyPopoverSize(animateResize: true)
    }

    private func schedulePopoverHeightUpdate(for measuredHeight: CGFloat) {
        popoverResizeTask?.cancel()
        popoverResizeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(30))
            guard Task.isCancelled == false else {
                return
            }
            self?.updatePopoverHeight(for: measuredHeight)
        }
    }

    private func applyPopoverSize(animateResize: Bool) {
        let screenHeight = popover.contentViewController?.view.window?.screen?.visibleFrame.height
            ?? statusItem?.button?.window?.screen?.visibleFrame.height
            ?? NSScreen.main?.visibleFrame.height
            ?? PopoverSizingPolicy.maximumPreferredHeight + PopoverSizingPolicy.screenMargin
        let height = PopoverSizingPolicy.height(
            forMeasuredContentHeight: measuredPopoverContentHeight,
            availableScreenHeight: screenHeight
        )
        let targetSize = NSSize(width: PopoverSizingPolicy.width, height: height)
        let targetNeedsUpdate = abs(targetPopoverHeight - height) > 0.5
        let popoverNeedsUpdate = abs(popover.contentSize.width - targetSize.width) > 0.5
            || abs(popover.contentSize.height - targetSize.height) > 0.5

        guard targetNeedsUpdate || popoverNeedsUpdate else {
            return
        }

        targetPopoverHeight = height
        let shouldAnimate = PopoverAnimationPolicy.shouldAnimateResize(
            requested: animateResize,
            isPopoverShown: popover.isShown,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )

        guard shouldAnimate else {
            popover.animates = false
            popover.contentSize = targetSize
            return
        }

        // NSPopover keeps its arrow anchored while animating contentSize changes.
        popover.animates = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = PopoverAnimationPolicy.resizeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            popover.contentSize = targetSize
        }
    }

    private func makePopoverWindowTranslucent() {
        guard let window = popover.contentViewController?.view.window else {
            return
        }

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
    }
}
