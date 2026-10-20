import Foundation
import MacSystemMetrics

/// A running Claude Code session.
struct AgentSession: Identifiable, Equatable, Sendable {
    let pid: Int32
    let title: String
    let directory: URL
    let isBusy: Bool
    let startedAt: Date
    /// The session process with the tools and servers it started.
    let usage: ProcessTreeUsage

    var id: Int32 { pid }
    var project: String { ClaudeSessions.project(of: directory.path) }
}

/// Claude Code registers each session in a file named by its pid, which stays behind when the process ends.
enum ClaudeSessions {
    static let registryPath = ".claude/sessions"

    struct Record: Decodable, Equatable {
        let pid: Int32
        let cwd: String
        /// Milliseconds since 1970, a moment after the process started.
        let startedAt: Double
        let name: String?
        /// "busy" while working, "idle" while waiting for the user.
        let status: String?
    }

    /// Reads small registry files and the process list, so it is quick enough for the main thread.
    static func read(home: URL) throws(MetricError) -> [AgentSession] {
        sessions(records(in: home.appending(path: registryPath)), nodes: try ProcessTree.nodes())
    }

    /// Records whose process is still the one that registered: a process that started after registration has
    /// reused the pid of one that ended. Newest first.
    static func sessions(_ records: [Record], nodes: [ProcessNode]) -> [AgentSession] {
        let started = Dictionary(nodes.map { ($0.pid, $0.startedAt) }, uniquingKeysWith: { first, _ in first })
        let live = records.filter { record in
            started[record.pid].map { $0 <= Date(timeIntervalSince1970: record.startedAt / 1000) } == true
        }
        let usage = ProcessTree.usage(of: Set(live.map(\.pid)), in: nodes)
        return live.compactMap { record in
            guard let usage = usage[record.pid] else { return nil }
            let directory = URL(fileURLWithPath: record.cwd)
            return AgentSession(
                pid: record.pid,
                title: record.name.flatMap { $0.isEmpty ? nil : $0 } ?? project(of: record.cwd),
                directory: directory,
                isBusy: record.status == "busy",
                startedAt: Date(timeIntervalSince1970: record.startedAt / 1000),
                usage: usage
            )
        }
        .sorted { $0.startedAt != $1.startedAt ? $0.startedAt > $1.startedAt : $0.pid < $1.pid }
    }

    /// The project a directory belongs to; a Claude Code worktree is named after its project, not itself.
    static func project(of path: String) -> String {
        let root = path.range(of: "/.claude/worktrees/").map { String(path[..<$0.lowerBound]) } ?? path
        return URL(fileURLWithPath: root).lastPathComponent
    }

    private static func records(in directory: URL) -> [Record] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        // A file being rewritten may fail to decode for a moment; it is read again on the next refresh.
        return files.filter { $0.pathExtension == "json" }.compactMap { file in
            (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode(Record.self, from: $0) }
        }
    }
}
