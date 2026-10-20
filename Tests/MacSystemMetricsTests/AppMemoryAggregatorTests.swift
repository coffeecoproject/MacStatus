import Testing
@testable import MacSystemMetrics

struct AppMemoryAggregatorTests {
    private let claude = "/Applications/Claude.app"
    private let docker = "/Applications/Docker.app"

    @Test func helpersCountTowardTheirOutermostApp() throws {
        let top = AppMemoryAggregator.top([
            ProcessSample(path: "\(claude)/Contents/MacOS/Claude", footprint: 300),
            ProcessSample(
                path: "\(claude)/Contents/Frameworks/Claude Helper (Renderer).app/Contents/MacOS/Claude Helper (Renderer)",
                footprint: 900
            )
        ], apps: [claude], limit: 5)

        let app = try #require(top.first)
        #expect(top.count == 1)
        #expect(app.bundlePath == claude)
        #expect(app.name == "Claude")
        #expect(app.processCount == 2)
        #expect(app.footprint == 1_200)
    }

    @Test func leavesOutProcessesOutsideTheListedApps() {
        let top = AppMemoryAggregator.top([
            ProcessSample(path: "/opt/homebrew/bin/node", footprint: 5_000),
            ProcessSample(path: "/System/Library/Frameworks/Virtualization.framework/XPCServices/VM.xpc/Contents/MacOS/VM", footprint: 4_000),
            ProcessSample(path: "/Library/Input Methods/SogouInput.app/Contents/MacOS/SogouInput", footprint: 3_000),
            ProcessSample(path: "\(docker)/Contents/MacOS/Docker Desktop.app/Contents/MacOS/Docker Desktop", footprint: 100)
        ], apps: [docker], limit: 5)

        #expect(top.map(\.bundlePath) == [docker])
        #expect(AppMemoryAggregator.top([
            ProcessSample(path: "\(claude)/Contents/MacOS/Claude", footprint: 1)
        ], apps: [], limit: 5).isEmpty)
    }

    @Test func keepsOnlyTheLargestApps() {
        let bundles = (1...8).map { "/Applications/A\($0).app" }
        let samples = bundles.enumerated().map {
            ProcessSample(path: "\($1)/Contents/MacOS/a", footprint: UInt64($0 + 1) * 10)
        }
        #expect(AppMemoryAggregator.top(samples, apps: Set(bundles), limit: 3).map(\.footprint) == [80, 70, 60])
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
