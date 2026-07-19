import AppKit
import Combine
import QuartzCore
import SwiftUI

/// Borderless panel that mirrors the Mac notch as a Dynamic Island–style widget.
/// Collapsed to notch width by default; expands on hover (BoringNotch pattern).
@MainActor
final class NotchWindowEngine {
    private let panel: NSPanel
    private let hostingView: NSHostingView<AnyView>
    private let appState: AppState
    private let menuBarAppearance = MenuBarAppearance()

    private var mouseMonitor: Any?
    private var localMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    private var collapseWorkItem: DispatchWorkItem?

    private let expandedSize = CGSize(width: 420, height: 224)
    private let panelOpenSize = CGSize(width: 420, height: 430)
    private let collapsedShoulderWidth: CGFloat = 58
    private let hoverCollapseDelay: TimeInterval = 0.34
    /// Keep the island centered on the notch so it does not slide over
    /// neighboring menu-bar items while expanding.
    private let expandedHorizontalOffset: CGFloat = 0

    init(appState: AppState) {
        self.appState = appState

        let root = NotchWidgetView()
            .environmentObject(appState)
            .environmentObject(menuBarAppearance)
            .tint(SeraTheme.progress)

        hostingView = NSHostingView(rootView: AnyView(root))
        hostingView.frame = NSRect(origin: .zero, size: CGSize(width: 180, height: 34))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.autoresizingMask = [.width, .height]

        panel = NSPanel(
            contentRect: hostingView.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = hostingView
        // Transparent outside SwiftUI's clip so rounded corners stay visible.
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = false
        panel.animationBehavior = .utilityWindow

        applyFrame(expanded: false, animate: false)
        panel.orderFrontRegardless()

        menuBarAppearance.start()

        startMouseTracking()
        observeState()
        observeScreens()
    }

    func destroy() {
        collapseWorkItem?.cancel()
        menuBarAppearance.stop()
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        mouseMonitor = nil
        localMonitor = nil
        screenObserver = nil
        cancellables.removeAll()
        appState.setNotchExpanded(false)
        panel.orderOut(nil)
        panel.close()
    }

    // MARK: - Layout

    private func applyFrame(expanded: Bool, animate: Bool) {
        guard let info = NotchGeometry.info() else { return }

        let target: NSRect
        if expanded {
            let preferredSize = appState.isPanelOpen ? panelOpenSize : expandedSize
            let size = CGSize(
                width: min(preferredSize.width, info.screen.frame.width - 40),
                height: preferredSize.height
            )
            target = NotchGeometry.expandedFrame(
                info: info,
                size: size,
                horizontalOffset: expandedHorizontalOffset
            )
        } else {
            target = NotchGeometry.collapsedFrame(
                info: info,
                horizontalPadding: collapsedShoulderWidth
            )
        }
        panel.hasShadow = false
        hostingView.frame = NSRect(origin: .zero, size: target.size)

        if animate {
            // Keep the top edge pinned and grow downward / outward — matches
            // the SwiftUI clip morph timing curve.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.42
                context.timingFunction = CAMediaTimingFunction(
                    controlPoints: 0.16,
                    1.0,
                    0.30,
                    1.0
                )
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
        }
    }

    // MARK: - Hover

    private func startMouseTracking() {
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.handleMouse(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            self?.handleMouse(event)
            return event
        }
    }

    private func handleMouse(_ event: NSEvent) {
        let point = NSEvent.mouseLocation
        let hitExpanded = panel.frame.insetBy(dx: -6, dy: -6).contains(point)

        // Also treat the physical notch band as a hover target while collapsed,
        // so moving onto the notch (even slightly outside the panel) expands.
        let hitNotch: Bool
        if let info = NotchGeometry.info() {
            let band = NotchGeometry.collapsedFrame(
                info: info,
                horizontalPadding: collapsedShoulderWidth
            )
            .insetBy(dx: -10, dy: -4)
            hitNotch = band.contains(point)
        } else {
            hitNotch = false
        }

        if hitExpanded || hitNotch {
            cancelScheduledCollapse()
            if !appState.isNotchExpanded {
                appState.setNotchExpanded(true)
            }
        } else if appState.isNotchExpanded, !appState.isPanelOpen {
            scheduleCollapse()
        }
    }

    private func scheduleCollapse() {
        guard collapseWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.collapseWorkItem = nil
            let point = NSEvent.mouseLocation
            if self.panel.frame.insetBy(dx: -6, dy: -6).contains(point) { return }
            self.appState.setNotchExpanded(false)
        }
        collapseWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + hoverCollapseDelay, execute: work)
    }

    private func cancelScheduledCollapse() {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
    }

    // MARK: - Observation

    private func observeState() {
        appState.$isNotchExpanded
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] expanded in
                self?.applyFrame(expanded: expanded || (self?.appState.isPanelOpen ?? false), animate: true)
            }
            .store(in: &cancellables)

        appState.$isPanelOpen
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] open in
                guard let self else { return }
                if open {
                    self.cancelScheduledCollapse()
                    self.appState.setNotchExpanded(true)
                }
                self.applyFrame(
                    expanded: self.appState.isNotchExpanded || open,
                    animate: true
                )
            }
            .store(in: &cancellables)

        appState.$displayMode
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in
                if mode.showsNotch {
                    self?.panel.orderFrontRegardless()
                    self?.applyFrame(
                        expanded: self?.appState.isNotchExpanded == true,
                        animate: false
                    )
                } else {
                    self?.panel.orderOut(nil)
                }
            }
            .store(in: &cancellables)
    }

    private func observeScreens() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.menuBarAppearance.refresh()
                self.applyFrame(
                    expanded: self.appState.isNotchExpanded || self.appState.isPanelOpen,
                    animate: false
                )
            }
        }
    }
}
