import AppKit
import MacSystemMetrics

/// Regular apps, the ones in the Dock and the Force Quit window, which may be asked to quit normally.
/// Menu bar apps, background agents and command-line tools are not listed, nor is Finder, which has no Quit.
@MainActor
enum QuittableApps {
    /// Their outermost bundles, as the app list groups processes.
    static func bundlePaths() -> Set<String> {
        Set(running().map(\.bundle))
    }

    /// Same as choosing Quit in the app: it may ask to save, or decline.
    static func quit(bundlePath: String) {
        for (app, bundle) in running() where bundle == bundlePath {
            _ = app.terminate()
        }
    }

    private static func running() -> [(app: NSRunningApplication, bundle: String)] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.activationPolicy == .regular, app.bundleIdentifier != "com.apple.finder", let url = app.bundleURL,
                  let bundle = AppMemoryUsage.bundlePath(containing: url.resolvingSymlinksInPath().path)
            else { return nil }
            return (app, bundle)
        }
    }
}
