import Darwin
import Testing
@testable import MacSystemMetrics

struct AppMemoryAggregatorTests {
    private let claude = "/Applications/Claude.app"
    private let docker = "/Applications/Docker.app"

    @Test func helpersCountTowardTheirOutermostApp() throws {
        let top = AppMemoryAggregator.usages([
            ProcessSample(path: "\(claude)/Contents/MacOS/Claude", footprint: 300),
            ProcessSample(
                path: "\(claude)/Contents/Frameworks/Claude Helper (Renderer).app/Contents/MacOS/Claude Helper (Renderer)",
                footprint: 900
            )
        ], apps: [claude])

        let app = try #require(top.first)
        #expect(top.count == 1)
        #expect(app.bundlePath == claude)
        #expect(app.name == "Claude")
        #expect(app.processCount == 2)
        #expect(app.footprint == 1_200)
    }

    @Test func processesRunFromElsewhereCountTowardTheAppResponsibleForThem() throws {
        let safari = "/Applications/Safari.app"
        let top = AppMemoryAggregator.usages([
            ProcessSample(path: "\(safari)/Contents/MacOS/Safari", footprint: 100),
            ProcessSample(
                path: "/System/Library/Frameworks/WebKit.framework/XPCServices/com.apple.WebKit.WebContent.xpc/Contents/MacOS/com.apple.WebKit.WebContent",
                responsiblePath: "\(safari)/Contents/MacOS/Safari",
                footprint: 700
            ),
            ProcessSample(
                path: "/System/Library/Frameworks/Virtualization.framework/XPCServices/VM.xpc/Contents/MacOS/VM",
                responsiblePath: "\(docker)/Contents/MacOS/com.docker.backend",
                footprint: 4_000
            )
        ], apps: [safari, docker])

        #expect(top.map(\.bundlePath) == [docker, safari])
        #expect(top.map(\.footprint) == [4_000, 800])
        #expect(try #require(top.last).processCount == 2)
    }

    @Test func aProcessRunFromAListedAppCountsTowardItWhoeverIsResponsible() {
        let terminal = "/System/Applications/Utilities/Terminal.app"
        let top = AppMemoryAggregator.usages([
            ProcessSample(
                path: "\(claude)/Contents/MacOS/Claude",
                responsiblePath: "\(terminal)/Contents/MacOS/Terminal",
                footprint: 300
            ),
            ProcessSample(
                path: "/opt/homebrew/bin/node",
                responsiblePath: "\(terminal)/Contents/MacOS/Terminal",
                footprint: 50
            )
        ], apps: [claude, terminal])

        #expect(top.map(\.bundlePath) == [claude, terminal])
        #expect(top.map(\.footprint) == [300, 50])
    }

    /// The lookup degrades quietly by design, so this is what notices a macOS that dropped it.
    @Test func theResponsibilityLookupIsAvailable() throws {
        let responsiblePID = try #require(Responsibility.responsiblePID)
        #expect(responsiblePID(getpid()) > 0)
    }

    @Test func leavesOutProcessesOutsideTheListedApps() {
        let top = AppMemoryAggregator.usages([
            ProcessSample(path: "/opt/homebrew/bin/node", footprint: 5_000),
            ProcessSample(
                path: "/System/Library/Frameworks/Virtualization.framework/XPCServices/VM.xpc/Contents/MacOS/VM",
                responsiblePath: "/Applications/Menu Bar Tool.app/Contents/MacOS/tool",
                footprint: 4_000
            ),
            ProcessSample(path: "/Library/Input Methods/SogouInput.app/Contents/MacOS/SogouInput", footprint: 3_000),
            ProcessSample(path: "\(docker)/Contents/MacOS/Docker Desktop.app/Contents/MacOS/Docker Desktop", footprint: 100)
        ], apps: [docker])

        #expect(top.map(\.bundlePath) == [docker])
        #expect(AppMemoryAggregator.usages([
            ProcessSample(path: "\(claude)/Contents/MacOS/Claude", footprint: 1)
        ], apps: []).isEmpty)
    }

    @Test func sortsTheAppsLargestFirst() {
        let bundles = (1...4).map { "/Applications/A\($0).app" }
        let samples = bundles.enumerated().map {
            ProcessSample(path: "\($1)/Contents/MacOS/a", footprint: UInt64($0 + 1) * 10)
        }
        #expect(AppMemoryAggregator.usages(samples, apps: Set(bundles)).map(\.footprint) == [40, 30, 20, 10])
    }

    @Test(arguments: [
        ("/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal", "/System/Applications/Utilities/Terminal.app"),
        ("/Applications/Claude.app", "/Applications/Claude.app"),
        ("/Applications/Claude.app/", "/Applications/Claude.app"),
        ("/Applications/Docker.app/Contents/MacOS/Docker Desktop.app", "/Applications/Docker.app"),
        ("/Applications/Docker.app2/Contents/MacOS/x", nil),
        ("/Users/me/tools/build.app.bak/bin/tool", nil),
        ("/usr/libexec/trustd", nil)
    ] as [(String, String?)])
    func bundlePathIsTheOutermostAppDirectory(path: String, expected: String?) {
        #expect(AppMemoryUsage.bundlePath(containing: path) == expected)
    }
}
