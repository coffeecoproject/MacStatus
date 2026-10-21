import AppKit

@main
@MainActor
enum MacStatusApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = SystemMonitor()
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController(monitor: monitor)

        // Nothing is shown while the system sleeps or the displays are off, so nothing is sampled.
        let notifications = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            notifications.addObserver(self, selector: #selector(pause), name: name, object: nil)
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            notifications.addObserver(self, selector: #selector(resume), name: name, object: nil)
        }
        monitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        monitor.pause()
        menuBar?.invalidate()
    }

    @objc private func pause(_ notification: Notification) {
        monitor.pause()
    }

    @objc private func resume(_ notification: Notification) {
        monitor.start()
    }
}
