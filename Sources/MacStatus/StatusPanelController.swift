import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusPanelController: NSObject, NSWindowDelegate {
    private static let cornerRadius: CGFloat = 12

    private let monitor: SystemMonitor
    private let model = PanelModel()
    private let cleanup = CleanupModel()
    private let hosting: NSHostingController<StatusPanelView>
    private let panel = MetricsPanel(
        contentRect: .zero,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    private weak var anchorButton: NSStatusBarButton?
    private var observedAnchorWindow: NSWindow?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var subscriptions: [AnyCancellable] = []

    init(monitor: SystemMonitor) {
        self.monitor = monitor
        hosting = NSHostingController(rootView: StatusPanelView(monitor: monitor, model: model, cleanup: cleanup))
        super.init()
        subscriptions = [
            model.$page.dropFirst().sink { [weak self] _ in
                self?.pageChanged()
            },
            // Reported during layout; refit on the next main-queue turn, outside it.
            model.$contentHeight.removeDuplicates().dropFirst().receive(on: DispatchQueue.main).sink { [weak self] _ in
                self?.fitContent()
            }
        ]

        // The controller sizes and places the panel; SwiftUI must not resize/reposition the window.
        hosting.sizingOptions = []
        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = .roundedMask(radius: Self.cornerRadius)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: background.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: background.bottomAnchor)
        ])
        panel.contentView = background
        panel.delegate = self
        panel.title = "MacStatus 指标面板"
        panel.setAccessibilityIdentifier("MacStatusMetricsPanel")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        panel.onCancel = { [weak self] in self?.hide() }
    }

    func toggle(relativeTo button: NSStatusBarButton) {
        if panel.isVisible {
            hide()
            return
        }
        anchorButton = button
        guard positionPanel(), startObservingDismissal() else {
            hide()
            return
        }
        panel.makeKeyAndOrderFront(nil)
        monitor.setPanelDemand(panel.isVisible ? demand : .hidden)
    }

    func hide() {
        stopObservingDismissal()
        panel.orderOut(nil)
        anchorButton = nil
        monitor.setPanelDemand(.hidden)
    }

    func invalidate() {
        subscriptions.removeAll()
        hide()
        panel.close()
    }

    private var demand: PanelDemand {
        switch model.page {
        case .overview, .cleanup: .metrics
        case .processes: .processes
        }
    }

    private func pageChanged() {
        guard panel.isVisible else { return }
        monitor.setPanelDemand(demand)
    }

    /// Keeps the top edge under the menu bar as the content height changes.
    private func fitContent() {
        if panel.isVisible, !positionPanel() { hide() }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Let the status item's mouse-up action toggle or open its exit menu.
        if NSEvent.pressedMouseButtons != 0,
           anchorRect?.contains(NSEvent.mouseLocation) == true { return }
        hide()
    }

    private var anchorRect: NSRect? {
        guard let button = anchorButton, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    @discardableResult
    private func positionPanel() -> Bool {
        guard let anchor = anchorRect,
              let screen = NSScreen.screens.first(where: {
                  $0.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY))
              }) else { return false }
        let size = hosting.sizeThatFits(in: screen.visibleFrame.size)
        guard size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return false }
        let frame = PanelPlacement.frame(
            contentSize: size,
            anchor: anchor,
            screenFrame: screen.frame,
            visibleFrame: screen.visibleFrame,
            menuBarHeight: max(NSStatusBar.system.thickness, screen.safeAreaInsets.top)
        )
        guard frame != panel.frame else { return true }
        panel.setFrame(frame, display: panel.isVisible)
        hosting.view.layoutSubtreeIfNeeded()
        panel.invalidateShadow()
        return true
    }

    private func startObservingDismissal() -> Bool {
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: clicks) { [weak self] event in
            self?.dismissIfOutside()
            return event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            self?.dismissIfOutside()
        }
        guard localMouseMonitor != nil, globalMouseMonitor != nil else { return false }

        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(
            self, selector: #selector(activeApplicationChanged),
            name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.willSleepNotification] {
            workspace.addObserver(self, selector: #selector(dismissForSystemChange), name: name, object: nil)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(dismissForSystemChange),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        if let window = anchorButton?.window {
            observedAnchorWindow = window
            NotificationCenter.default.addObserver(
                self, selector: #selector(anchorMoved),
                name: NSWindow.didMoveNotification, object: window
            )
        }
        return true
    }

    private func stopObservingDismissal() {
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        localMouseMonitor = nil
        globalMouseMonitor = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(
            self, name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        if let observedAnchorWindow {
            NotificationCenter.default.removeObserver(
                self, name: NSWindow.didMoveNotification, object: observedAnchorWindow
            )
        }
        observedAnchorWindow = nil
    }

    private func dismissIfOutside() {
        guard panel.isVisible else { return }
        let point = NSEvent.mouseLocation
        if panel.frame.contains(point) || anchorRect?.contains(point) == true { return }
        hide()
    }

    @objc private func activeApplicationChanged(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
        hide()
    }

    @objc private func dismissForSystemChange(_ notification: Notification) {
        hide()
    }

    @objc private func anchorMoved(_ notification: Notification) {
        fitContent()
    }
}

private extension NSImage {
    /// Stretchable mask that rounds a visual effect view's corners, shadow included.
    static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

@MainActor
private final class MetricsPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
