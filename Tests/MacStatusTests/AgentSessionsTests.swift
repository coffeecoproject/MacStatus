import Foundation
@testable import MacSystemMetrics
import Testing
@testable import MacStatus

struct AgentSessionsTests {
    private let registeredAt = Date(timeIntervalSince1970: 1_000_000)

    private func record(_ pid: Int32, cwd: String = "/Users/me/Developer/MacStatus", name: String? = "任务", status: String? = "idle", after seconds: Double = 0) -> ClaudeSessions.Record {
        ClaudeSessions.Record(pid: pid, cwd: cwd, startedAt: (registeredAt.timeIntervalSince1970 + seconds) * 1000, name: name, status: status)
    }

    private func node(_ pid: Int32, parent: Int32 = 1, startedAt: Date, footprint: UInt64 = 100) -> ProcessNode {
        ProcessNode(pid: pid, parent: parent, startedAt: startedAt, footprint: footprint)
    }

    @Test func leavesOutEndedSessionsAndPidsReusedAfterRegistration() {
        let sessions = ClaudeSessions.sessions(
            [record(10), record(20), record(30)],
            nodes: [
                node(10, startedAt: registeredAt.addingTimeInterval(-2)),
                // Started after the session registered: a different process with the same pid.
                node(20, startedAt: registeredAt.addingTimeInterval(60))
            ]
        )
        #expect(sessions.map(\.pid) == [10])
    }

    @Test func countsChildProcessesAndReadsStatus() throws {
        let started = registeredAt.addingTimeInterval(-2)
        let sessions = ClaudeSessions.sessions(
            [record(10, status: "busy")],
            nodes: [node(10, startedAt: started, footprint: 300), node(11, parent: 10, startedAt: started, footprint: 50)]
        )
        let session = try #require(sessions.first)
        #expect(session.isBusy)
        #expect(session.usage == ProcessTreeUsage(processCount: 2, footprint: 350))
    }

    @Test func untitledSessionsUseTheProjectNameAndNewestComeFirst() {
        let sessions = ClaudeSessions.sessions(
            [record(10, name: nil), record(20, name: "", after: 5), record(30, name: "新的", after: 10)],
            nodes: [10, 20, 30].map { node($0, startedAt: registeredAt.addingTimeInterval(-2)) }
        )
        #expect(sessions.map(\.title) == ["新的", "MacStatus", "MacStatus"])
        #expect(sessions.map(\.pid) == [30, 20, 10])
    }

    @Test func worktreesBelongToTheirProject() {
        #expect(ClaudeSessions.project(of: "/Users/me/Developer/Pawcode/.claude/worktrees/priceless-poincare") == "Pawcode")
        #expect(ClaudeSessions.project(of: "/Users/me/Developer/Pawcode") == "Pawcode")
    }
}
