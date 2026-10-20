import AppKit

guard CommandLine.arguments.count == 2, let pid = Int32(CommandLine.arguments[1]) else { exit(2) }
let deadline = ContinuousClock.now.advanced(by: .seconds(6))
while ContinuousClock.now < deadline {
    if let app = NSRunningApplication(processIdentifier: pid) {
        if app.isTerminated { exit(2) }
        if app.isFinishedLaunching { exit(0) }
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
}
exit(1)
