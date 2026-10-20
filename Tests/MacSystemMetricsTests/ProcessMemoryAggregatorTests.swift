import Testing
@testable import MacSystemMetrics

struct ProcessMemoryAggregatorTests {
    @Test func helpersCountTowardTheirOutermostApp() throws {
        let top = ProcessMemoryAggregator.top([
            ProcessSample(pid: 10, name: "Claude", path: "/Applications/Claude.app/Contents/MacOS/Claude", footprint: 300),
            ProcessSample(
                pid: 11, name: "Claude Helper (Renderer)",
                path: "/Applications/Claude.app/Contents/Frameworks/Claude Helper (Renderer).app/Contents/MacOS/Claude Helper (Renderer)",
                footprint: 900
            ),
            ProcessSample(pid: 20, name: "node", path: "/opt/homebrew/bin/node", footprint: 1_000)
        ], limit: 5)

        let app = try #require(top.first)
        #expect(app.id == "/Applications/Claude.app")
        #expect(app.name == "Claude")
        #expect(app.bundlePath == "/Applications/Claude.app")
        #expect(app.processCount == 2)
        #expect(app.footprint == 1_200)
        #expect(top.map(\.id) == ["/Applications/Claude.app", "pid:20"])
    }

    @Test func standaloneProcessesStaySeparateEvenWithTheSameName() {
        let top = ProcessMemoryAggregator.top([
            ProcessSample(pid: 1, name: "node", path: "/opt/homebrew/bin/node", footprint: 100),
            ProcessSample(pid: 2, name: "node", path: "/opt/homebrew/bin/node", footprint: 100),
            ProcessSample(pid: 3, name: "zombie", path: nil, footprint: 50)
        ], limit: 5)

        #expect(top.map(\.id) == ["pid:1", "pid:2", "pid:3"])
        #expect(top.allSatisfy { $0.bundlePath == nil && $0.processCount == 1 })
        #expect(top.last?.name == "zombie")
    }

    @Test func keepsOnlyTheLargestGroups() {
        let samples = (1...8).map {
            ProcessSample(pid: Int32($0), name: "p\($0)", path: nil, footprint: UInt64($0) * 10)
        }
        #expect(ProcessMemoryAggregator.top(samples, limit: 3).map(\.footprint) == [80, 70, 60])
    }

    @Test(arguments: [
        ("/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal", "/System/Applications/Utilities/Terminal.app"),
        ("/Users/me/tools/build.app.bak/bin/tool", nil),
        ("/usr/libexec/trustd", nil)
    ] as [(String, String?)])
    func bundlePathRequiresAnAppDirectory(path: String, expected: String?) {
        #expect(ProcessMemoryAggregator.bundlePath(forExecutable: path) == expected)
    }
}
