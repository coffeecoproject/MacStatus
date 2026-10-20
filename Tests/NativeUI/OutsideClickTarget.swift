import AppKit

func emit(_ event: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: event)
    FileHandle.standardOutput.write(data + Data([0x0a]))
}

@MainActor
final class ClickView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        emit(["event": "click"])
    }
}

@MainActor
final class TargetDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var activationObserver: NSObjectProtocol?
    private var mouseObserver: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else { exit(2) }
        let frame = screen.visibleFrame
        let window = NSWindow(
            contentRect: NSRect(x: frame.minX + 24, y: frame.minY + 24, width: 320, height: 100),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.title = "MacStatus 交互测试（临时）"
        window.contentView = ClickView()
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        self.window = window
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                emit(["event": "activation", "pid": Int(app.processIdentifier)])
            }
        }
        mouseObserver = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp]
        ) { event in
            emit([
                "event": "mouse",
                "type": event.type.rawValue,
                "sourcePID": event.cgEvent?.getIntegerValueField(.eventSourceUnixProcessID) ?? -1,
                "receivedAt": ProcessInfo.processInfo.systemUptime
            ])
        }
        emit([
            "event": "ready",
            "x": window.frame.midX,
            "y": NSScreen.screens[0].frame.maxY - window.frame.midY
        ])
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = TargetDelegate()
app.delegate = delegate
withExtendedLifetime(delegate) { app.run() }
