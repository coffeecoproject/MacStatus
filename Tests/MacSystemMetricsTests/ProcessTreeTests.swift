import Foundation
import Testing
@testable import MacSystemMetrics

struct ProcessTreeTests {
    private func node(_ pid: pid_t, parent: pid_t, footprint: UInt64) -> ProcessNode {
        ProcessNode(pid: pid, parent: parent, startedAt: Date(timeIntervalSince1970: 0), footprint: footprint)
    }

    @Test func rootCountsEveryDescendantButNotItsParentOrSiblings() throws {
        let nodes = [
            node(1, parent: 0, footprint: 1_000),
            node(10, parent: 1, footprint: 100),
            node(11, parent: 10, footprint: 20),
            node(12, parent: 11, footprint: 3),
            node(20, parent: 1, footprint: 500)
        ]
        let usage = try #require(ProcessTree.usage(of: [10], in: nodes)[10])
        #expect(usage == ProcessTreeUsage(processCount: 3, footprint: 123))
    }

    @Test func rootsNotListedAreLeftOut() {
        let usage = ProcessTree.usage(of: [10, 99], in: [node(10, parent: 1, footprint: 5)])
        #expect(Set(usage.keys) == [10])
    }

    @Test func aLoopFromReusedPidsCountsEachProcessOnce() throws {
        let nodes = [node(10, parent: 11, footprint: 1), node(11, parent: 10, footprint: 2)]
        let usage = try #require(ProcessTree.usage(of: [10], in: nodes)[10])
        #expect(usage == ProcessTreeUsage(processCount: 2, footprint: 3))
    }
}
