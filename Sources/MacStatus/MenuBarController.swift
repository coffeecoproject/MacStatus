import AppKit
import Combine

@MainActor
final class MenuBarController: NSObject {
    private static let selectionKey = "menuBarMetrics"

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let panel: StatusPanelController
    private let monitor: SystemMonitor
    private var subscription: AnyCancellable?
    private var renderedTexts: [String]?

    private var selection: [MenuBarMetric] {
        get {
            guard let stored = UserDefaults.standard.stringArray(forKey: Self.selectionKey) else {
                return MenuBarMetric.defaultSelection
            }
            return MenuBarMetric.allCases.filter { stored.contains($0.rawValue) }
        }
        set {
            UserDefaults.standard.set(newValue.map(\.rawValue), forKey: Self.selectionKey)
        }
    }

    init(monitor: SystemMonitor) {
        self.monitor = monitor
        panel = StatusPanelController(monitor: monitor)
        super.init()

        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("MacStatus")
            button.setAccessibilityCustomActions([
                NSAccessibilityCustomAction(name: "显示菜单", target: self, selector: #selector(showMenu))
            ])
        }

        subscription = monitor.$snapshot.sink { [weak self] snapshot in
            self?.render(snapshot)
        }
    }

    func invalidate() {
        subscription?.cancel()
        subscription = nil
        panel.invalidate()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func render(_ snapshot: MonitorSnapshot) {
        let metrics = selection
        let texts = metrics.map { $0.text(snapshot) }
        guard texts != renderedTexts, let button = statusItem.button else { return }
        renderedTexts = texts
        if metrics.isEmpty {
            button.image = NSImage(systemSymbolName: "gauge.with.dots.needle.33percent", accessibilityDescription: nil)
            button.image?.isTemplate = true
        } else {
            button.image = MenuBarRenderer.image(for: Array(zip(metrics, texts)))
        }
        button.setAccessibilityValue(
            zip(metrics, texts).map { "\($0.title) \($1)" }.joined(separator: "，")
        )
    }

    @objc private func handleClick() {
        if let event = NSApp.currentEvent,
           event.type == .rightMouseUp
            || (event.type == .leftMouseUp && event.modifierFlags.contains(.control)) {
            _ = showMenu()
        } else if let button = statusItem.button {
            panel.toggle(relativeTo: button)
        }
    }

    @objc private func showMenu() -> Bool {
        guard let button = statusItem.button else { return false }
        panel.hide()
        let menu = NSMenu()
        let header = NSMenuItem(title: "菜单栏显示", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        let current = selection
        for metric in MenuBarMetric.allCases {
            let item = NSMenuItem(title: metric.title, action: #selector(toggleMetric), keyEquivalent: "")
            item.target = self
            item.representedObject = metric.rawValue
            item.state = current.contains(metric) ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 MacStatus", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: button.bounds.minX, y: button.isFlipped ? button.bounds.maxY : button.bounds.minY),
            in: button
        )
        return true
    }

    @objc private func toggleMetric(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let metric = MenuBarMetric(rawValue: raw) else { return }
        var metrics = selection
        if let index = metrics.firstIndex(of: metric) {
            metrics.remove(at: index)
        } else {
            metrics.append(metric)
        }
        selection = metrics
        renderedTexts = nil
        render(monitor.snapshot)
    }
}
