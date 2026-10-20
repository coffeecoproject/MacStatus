import AppKit
import MacSystemMetrics

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
    private let monitor = SystemMonitor(
        cpuCollector: MachCPUCollector(),
        memoryCollector: MachMemoryCollector(),
        diskCollector: StartupDiskCollector(),
        temperatureCollector: SMCTemperatureCollector()
    )
    private var menuBar: MenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBar = MenuBarController(monitor: monitor)

        let notifications = NSWorkspace.shared.notificationCenter
        notifications.addObserver(
            self,
            selector: #selector(willSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        notifications.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        monitor.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        monitor.pause()
        menuBar?.invalidate()
    }

    @objc private func willSleep(_ notification: Notification) {
        monitor.pause()
    }

    @objc private func didWake(_ notification: Notification) {
        monitor.start()
    }
}
