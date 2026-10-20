import AppKit
import Combine
import MacStatusCore

@MainActor
final class MenuBarController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: 96)
    private let panel: StatusPanelController
    private let exitMenu = NSMenu()
    private var subscription: AnyCancellable?

    init(monitor: SystemMonitor) {
        panel = StatusPanelController(monitor: monitor)
        super.init()

        let quitItem = NSMenuItem(
            title: "退出 MacStatus",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        exitMenu.addItem(quitItem)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "cpu",
                accessibilityDescription: nil
            )
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.font = .monospacedDigitSystemFont(
                ofSize: NSFont.systemFontSize,
                weight: .regular
            )
            button.target = self
            button.action = #selector(handleStatusItemClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("CPU 使用率")
            button.setAccessibilityCustomActions([
                NSAccessibilityCustomAction(
                    name: "显示退出菜单", target: self, selector: #selector(showExitMenu)
                )
            ])
        }

        subscription = monitor.$snapshot
            .map(\.cpu)
            .removeDuplicates()
            .sink { [weak self] status in
                self?.update(status)
            }
    }

    func invalidate() {
        subscription?.cancel()
        subscription = nil
        exitMenu.cancelTracking()
        panel.invalidate()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func handleStatusItemClick() {
        if let event = NSApp.currentEvent,
           event.type == .rightMouseUp
            || (event.type == .leftMouseUp && event.modifierFlags.contains(.control)) {
            _ = showExitMenu()
        } else {
            togglePanel()
        }
    }

    @objc private func showExitMenu() -> Bool {
        guard let button = statusItem.button else { return false }
        panel.hide()
        let origin = NSPoint(
            x: button.bounds.minX,
            y: button.isFlipped ? button.bounds.maxY : button.bounds.minY
        )
        exitMenu.popUp(positioning: nil, at: origin, in: button)
        return true
    }

    private func togglePanel() {
        guard let button = statusItem.button else { return }
        panel.toggle(relativeTo: button)
    }

    private func update(_ status: CPUStatus) {
        statusItem.button?.title = " CPU \(status.percentageText)"
        statusItem.button?.setAccessibilityValue(status.accessibilitySummary)
    }
}
