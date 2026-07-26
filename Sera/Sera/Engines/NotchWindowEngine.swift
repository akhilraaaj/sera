import AppKit
import Combine
import QuartzCore
import SwiftUI

/// Borderless panel that mirrors the Mac notch as a Dynamic Island–style widget.
/// Window stays top-pinned at expanded size; SwiftUI morphs the island clip
/// between idle and expanded so hover never opens a gap under the menu bar.
@MainActor
final class NotchWindowEngine {
    private let panel: NSPanel
    private let hostingView: NSHostingView<AnyView>
    private let appState: AppState
    private let notchLayout = NotchLayout()

    private var mouseMonitor: Any?
    private var localMonitor: Any?
    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    private var collapseWorkItem: DispatchWorkItem?
    private var expandWorkItem: DispatchWorkItem?
    private var spaceExpandWorkItem: DispatchWorkItem?
    private var ignoreHoverUntil: Date = .distantPast

    private let expandedSize = CGSize(width: 560, height: 210)
    /// Shoulder width beside the camera cutout — leaves room for progress /
    /// percent inside the idle ear + bottom-corner silhouette.
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
        hostingView.frame = NSRect(origin: .zero, size: expandedSize)
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
    }

    func destroy() {
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
        mouseMonitor = nil
        localMonitor = nil
        screenObserver = nil
        spaceObserver = nil
        cancellables.removeAll()
        appState.setNotchExpanded(false)
        panel.orderOut(nil)
        panel.close()
    }

    // MARK: - Layout

    /// Panel always uses the expanded frame (top-pinned). Idle vs hover is a
    /// SwiftUI clip morph — no window height animation, so no menubar gap.
    private func applyWindowFrame() {
        guard let info = NotchGeometry.info() else { return }

        let idle = NotchGeometry.collapsedFrame(
            info: info,
            horizontalPadding: collapsedShoulderWidth
        )
        notchLayout.idleSize = idle.size

        let size = CGSize(
            width: min(expandedSize.width, info.screen.frame.width - 40),
            height: expandedSize.height
        )
        let target = NotchGeometry.expandedFrame(
            info: info,
            size: size,
            horizontalOffset: expandedHorizontalOffset
        )

        panel.hasShadow = false
        panel.setFrame(target, display: true)
        hostingView.frame = NSRect(origin: .zero, size: target.size)
        updateMouseEventPassthrough()
    }

    private func updateMouseEventPassthrough() {
        let interactive = appState.isNotchExpanded || appState.isPanelOpen
        panel.ignoresMouseEvents = !interactive
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
        guard Date() >= ignoreHoverUntil else { return }

        let point = NSEvent.mouseLocation
        let open = appState.isNotchExpanded || appState.isPanelOpen

        let hit: Bool
        if open {
            hit = panel.frame.insetBy(dx: -6, dy: -6).contains(point)
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
            if appState.isNotchExpanded, !appState.isPanelOpen {
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

        // Timelines stays open across spaces — don't interrupt it.
        guard !appState.isPanelOpen else {
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
