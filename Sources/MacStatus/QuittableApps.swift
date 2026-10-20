import AppKit

/// Regular (Dock) apps behind a process-list row, which may be asked to quit normally.
/// Menu bar apps, background agents, command-line tools and MacStatus itself are left alone.
@MainActor
enum QuittableApps {
    static func instances(in bundlePath: String) -> [NSRunningApplication] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.filter { app in
            guard app.activationPolicy == .regular, app.processIdentifier != ownPID,
                  let url = app.bundleURL else { return false }
            return contains(bundlePath, url.resolvingSymlinksInPath().path)
        }
    }

    /// A row groups everything under its outermost bundle, and the regular app may be nested inside it
    /// (Docker.app/Contents/MacOS/Docker Desktop.app).
    nonisolated static func contains(_ bundlePath: String, _ appPath: String) -> Bool {
        appPath == bundlePath || appPath.hasPrefix(bundlePath + "/")
    }

    /// Same as choosing Quit in the app: it may ask to save, or decline.
    static func quit(_ apps: [NSRunningApplication]) {
        for app in apps {
            _ = app.terminate()
        }
    }
}
