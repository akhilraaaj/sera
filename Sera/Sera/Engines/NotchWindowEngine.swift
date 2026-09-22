import AppKit
import Combine
import QuartzCore
import SwiftUI

/// Borderless panel that mirrors the Mac notch as a Dynamic Island–style widget.
/// Window stays top-pinned at expanded size; SwiftUI morphs the island clip
/// between idle and expanded so hover never opens a gap under the menu bar.
@MainActor
final class NotchWindowEngine {
    private let panel: NotchPanel
    private let hostingView: NSHostingView<AnyView>
    private let appState: AppState
    private let notchLayout = NotchLayout()

    private var mouseMonitor: Any?
    private var localMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var focusObservers: [NSObjectProtocol] = []
    private var cancellables = Set<AnyCancellable>()
    private var collapseWorkItem: DispatchWorkItem?
    private var expandWorkItem: DispatchWorkItem?
    private var spaceExpandWorkItem: DispatchWorkItem?
    private var heightAnimationID = 0
    private var interactiveIslandHeight: CGFloat = 210
    /// True while we resign key ourselves so that cleanup does not collapse the island.
    private var ignoringFocusLoss = false
    private var ignoreHoverUntil: Date = .distantPast

    private let collapsedShoulderWidth: CGFloat = 64
    /// Brief pause before morphing so hover/leave feel intentional, not jumpy.
    private let hoverExpandDelay: TimeInterval = 0.1
    private let hoverCollapseDelay: TimeInterval = 0.42
    /// Keep the island centered on the notch so it does not slide over
    /// neighboring menu-bar items while expanding.
    private let expandedHorizontalOffset: CGFloat = 0

    init(appState: AppState) {
        self.appState = appState

        let root = NotchWidgetView()
            .environmentObject(appState)
            .environmentObject(notchLayout)
            .tint(SeraTheme.progress)

        hostingView = NSHostingView(rootView: AnyView(root))
        hostingView.frame = NSRect(origin: .zero, size: notchLayout.composerSize)
        // The calendar must not resize the panel. Height changes are a clip morph.
        hostingView.sizingOptions = []
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.autoresizingMask = [.width, .height]

        panel = NotchPanel(
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
        // Idle: clicks pass through the transparent chrome; hover uses monitors.
        panel.ignoresMouseEvents = true
        // Avoid AppKit window chrome animations when the island is created/shown.
        panel.animationBehavior = .none

        applyWindowFrame()
        panel.orderFrontRegardless()

        // Ignore hover briefly so a cursor near the menu bar does not expand
        // the island in the same beat it appears (menu bar → notch handoff).
        ignoreHoverUntil = Date().addingTimeInterval(0.5)

        startMouseTracking()
        observeState()
        observeScreens()
        observeSpaceChanges()
        observeFocus()
    }

    func destroy() {
        heightAnimationID += 1
        collapseWorkItem?.cancel()
        expandWorkItem?.cancel()
        spaceExpandWorkItem?.cancel()
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
        for observer in focusObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        mouseMonitor = nil
        localMonitor = nil
        screenObserver = nil
        spaceObserver = nil
        focusObservers.removeAll()
        cancellables.removeAll()
        appState.setNotchExpanded(false)
        panel.orderOut(nil)
        panel.close()
    }

    // MARK: - Layout

    /// Panel stays at the tallest size, top-pinned. Idle, dashboard, and calendar
    /// are clip morphs inside that window so the frame never jumps.
    private func applyWindowFrame() {
        guard let info = NotchGeometry.info() else { return }

        let idle = NotchGeometry.collapsedFrame(
            info: info,
            horizontalPadding: collapsedShoulderWidth
        )
        notchLayout.idleSize = idle.size

        let size = CGSize(
            width: min(notchLayout.composerSize.width, info.screen.frame.width - 40),
            height: notchLayout.composerSize.height
        )
        let target = NotchGeometry.expandedFrame(
            info: info,
            size: size,
            horizontalOffset: expandedHorizontalOffset
        )

        panel.hasShadow = false
        panel.contentMinSize = target.size
        panel.contentMaxSize = target.size
        panel.setFrame(target, display: true)
        hostingView.frame = NSRect(origin: .zero, size: target.size)
        updateMouseEventPassthrough()
    }

    /// Screen rect of the black island, not the transparent window around it.
    private func visualIslandFrame() -> NSRect {
        let height = min(notchLayout.composerSize.height, max(notchLayout.dashboardSize.height, interactiveIslandHeight))
        return NSRect(
            x: panel.frame.minX,
            y: panel.frame.maxY - height,
            width: panel.frame.width,
            height: height
        )
    }

    private func updateMouseEventPassthrough() {
        let open = appState.isNotchExpanded || appState.isPanelOpen || appState.isAddGoalPresented
        let inside = visualIslandFrame().insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !(open && inside)
    }

    /// Text fields cannot take keys in a non-activating panel. While the
    /// composer is up, the island itself becomes the key window.
    private func setComposerKey(_ key: Bool) {
        if key {
            cancelScheduledCollapse()
            panel.allowsKeyInput = true
            panel.styleMask.remove(.nonactivatingPanel)
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            ignoringFocusLoss = true
            panel.allowsKeyInput = false
            if !panel.styleMask.contains(.nonactivatingPanel) {
                panel.styleMask.insert(.nonactivatingPanel)
            }
            if panel.isKeyWindow {
                panel.resignKey()
            }
            NSApp.deactivate()
            DispatchQueue.main.async { [weak self] in
                self?.ignoringFocusLoss = false
            }
        }
    }

    /// Matches the SwiftUI island spring so clicks follow the growing shell.
    private func animateInteractiveHeight(to target: CGFloat) {
        heightAnimationID += 1
        let animationID = heightAnimationID
        let from = interactiveIslandHeight
        let started = CACurrentMediaTime()
        stepInteractiveHeight(id: animationID, from: from, to: target, started: started)
    }

    private func stepInteractiveHeight(id: Int, from: CGFloat, to target: CGFloat, started: CFTimeInterval) {
        guard id == heightAnimationID else { return }
        let duration = 0.55
        let t = min(1, (CACurrentMediaTime() - started) / duration)
        interactiveIslandHeight = from + (target - from) * Self.ease(t)
        updateMouseEventPassthrough()
        guard t < 1 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60.0) { [weak self] in
            self?.stepInteractiveHeight(id: id, from: from, to: target, started: started)
        }
    }

    /// cubic-bezier(0.22, 1, 0.36, 1) — same curve as the notch spring.
    private static func ease(_ x: Double) -> Double {
        let x1 = 0.22
        let y1 = 1.0
        let x2 = 0.36
        let y2 = 1.0
        let cx = 3 * x1
        let bx = 3 * (x2 - x1) - cx
        let ax = 1 - cx - bx
        let cy = 3 * y1
        let by = 3 * (y2 - y1) - cy
        let ay = 1 - cy - by

        func sampleX(_ t: Double) -> Double { ((ax * t + bx) * t + cx) * t }
        func sampleY(_ t: Double) -> Double { ((ay * t + by) * t + cy) * t }
        func sampleDerivX(_ t: Double) -> Double { (3 * ax * t + 2 * bx) * t + cx }

        var t = x
        for _ in 0..<5 {
            let slope = sampleDerivX(t)
            if abs(slope) < 1e-6 { break }
            t -= (sampleX(t) - x) / slope
        }
        return sampleY(min(1, max(0, t)))
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
        updateMouseEventPassthrough()
        guard Date() >= ignoreHoverUntil else { return }

        let point = NSEvent.mouseLocation
        let open = appState.isNotchExpanded || appState.isPanelOpen || appState.isAddGoalPresented

        let hit: Bool
        if open {
            hit = visualIslandFrame().insetBy(dx: -6, dy: -6).contains(point)
        } else if let info = NotchGeometry.info() {
            // Only the idle island / notch band — not the full transparent window.
            hit = NotchGeometry.collapsedFrame(
                info: info,
                horizontalPadding: collapsedShoulderWidth
            )
            .insetBy(dx: -10, dy: -4)
            .contains(point)
        } else {
            hit = false
        }

        if hit {
            cancelScheduledCollapse()
            if !appState.isNotchExpanded {
                scheduleExpand()
            }
        } else {
            cancelScheduledExpand()
            guard !isCollapseSuppressed else {
                cancelScheduledCollapse()
                return
            }
            if appState.isNotchExpanded || appState.isPanelOpen || appState.isAddGoalPresented {
                scheduleCollapse()
            }
        }
    }

    private func scheduleExpand() {
        guard expandWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.expandWorkItem = nil
            let point = NSEvent.mouseLocation
            guard let info = NotchGeometry.info() else { return }
            let idleHit = NotchGeometry.collapsedFrame(
                info: info,
                horizontalPadding: self.collapsedShoulderWidth
            )
            .insetBy(dx: -10, dy: -4)
            .contains(point)
            guard idleHit else { return }
            self.appState.setNotchExpanded(true)
        }
        expandWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + hoverExpandDelay, execute: work)
    }

    private func cancelScheduledExpand() {
        expandWorkItem?.cancel()
        expandWorkItem = nil
    }

    private func scheduleCollapse() {
        guard collapseWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.collapseWorkItem = nil
            guard !self.isCollapseSuppressed else { return }
            let point = NSEvent.mouseLocation
            if self.visualIslandFrame().insetBy(dx: -6, dy: -6).contains(point) { return }
            self.appState.collapseNotch()
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
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateMouseEventPassthrough()
            }
            .store(in: &cancellables)

        appState.$isPanelOpen
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] open in
                guard let self else { return }
                if open {
                    self.cancelScheduledCollapse()
                    if !self.appState.isNotchExpanded {
                        self.appState.setNotchExpanded(true)
                    }
                }
                self.updateMouseEventPassthrough()
            }
            .store(in: &cancellables)

        appState.$isAddGoalPresented
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] presented in
                guard let self else { return }
                if presented, !self.appState.isNotchExpanded {
                    self.appState.setNotchExpanded(true)
                }
                self.animateInteractiveHeight(
                    to: presented ? self.notchLayout.composerSize.height : self.notchLayout.dashboardSize.height
                )
                self.updateMouseEventPassthrough()
                self.setComposerKey(presented)
            }
            .store(in: &cancellables)

        appState.$displayMode
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in
                if mode.showsNotch {
                    self?.panel.orderFrontRegardless()
                    self?.applyWindowFrame()
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
                self.applyWindowFrame()
            }
        }
    }

    /// Clicking another app resigns this panel. Collapse back to the idle island.
    private func observeFocus() {
        let resignActive = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.collapseFromFocusLoss()
            }
        }
        let resignKey = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.collapseFromFocusLoss()
            }
        }
        focusObservers.append(resignActive)
        focusObservers.append(resignKey)
    }

    private var isCollapseSuppressed: Bool {
        Date() < appState.suppressNotchCollapseUntil
    }

    private func collapseFromFocusLoss() {
        guard !ignoringFocusLoss, !isCollapseSuppressed else { return }
        // A click inside the island (delete, add, a menu) resigns key without
        // the pointer leaving. Only compress when focus moved off the island.
        if visualIslandFrame().insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation) {
            return
        }
        guard appState.isNotchExpanded || appState.isPanelOpen || appState.isAddGoalPresented else { return }
        cancelScheduledExpand()
        cancelScheduledCollapse()
        appState.collapseNotch()
    }

    /// Mission Control / desktop swipe / Cmd-Tab back to a space: snap to idle
    /// first, then morph open if the cursor sits on the notch so expand stays smooth.
    private func observeSpaceChanges() {
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDesktopOrSpaceBecameVisible()
            }
        }
    }

    private func handleDesktopOrSpaceBecameVisible() {
        applyWindowFrame()
        panel.orderFrontRegardless()

        // Timelines and the goal composer stay open across spaces.
        guard !appState.isPanelOpen, !appState.isAddGoalPresented else {
            updateMouseEventPassthrough()
            return
        }

        cancelScheduledExpand()
        cancelScheduledCollapse()
        spaceExpandWorkItem?.cancel()

        // Allow hover immediately after a space switch.
        ignoreHoverUntil = .distantPast

        // Always return to idle first so a follow-up expand can play the morph
        // (avoids appearing already-open when landing on the desktop).
        if appState.isNotchExpanded {
            appState.setNotchExpanded(false)
        }
        updateMouseEventPassthrough()

        guard isMouseOverIdleNotch() else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.spaceExpandWorkItem = nil
            guard !self.appState.isPanelOpen else { return }
            guard self.isMouseOverIdleNotch() else { return }
            self.appState.setNotchExpanded(true)
        }
        spaceExpandWorkItem = work
        // Brief beat so SwiftUI commits the idle clip before expanding.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    private func isMouseOverIdleNotch() -> Bool {
        guard let info = NotchGeometry.info() else { return false }
        return NotchGeometry.collapsedFrame(
            info: info,
            horizontalPadding: collapsedShoulderWidth
        )
        .insetBy(dx: -10, dy: -4)
        .contains(NSEvent.mouseLocation)
    }
}

/// Borderless notch panel that can accept keyboard focus while a goal is being named.
private final class NotchPanel: NSPanel {
    var allowsKeyInput = false

    override var canBecomeKey: Bool { allowsKeyInput }
    override var canBecomeMain: Bool { allowsKeyInput }
}
