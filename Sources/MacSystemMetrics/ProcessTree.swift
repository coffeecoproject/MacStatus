import Darwin
import Foundation

/// One of the current user's processes.
public struct ProcessNode: Sendable, Equatable {
    public let pid: pid_t
    public let parent: pid_t
    public let startedAt: Date
    /// Physical footprint, as in `AppMemoryUsage`.
    public let footprint: UInt64
}

/// Memory of a process together with every process under it.
public struct ProcessTreeUsage: Sendable, Equatable {
    public let processCount: Int
    public let footprint: UInt64
}

public enum ProcessTree {
    /// The current user's processes; other users' and root processes need privileges and are skipped.
    public static func nodes() throws(MetricError) -> [ProcessNode] {
        try ProcessList.pids().compactMap(node(pid:))
    }

    /// Each root that is among `nodes`, with its descendants.
    public static func usage(of roots: Set<pid_t>, in nodes: [ProcessNode]) -> [pid_t: ProcessTreeUsage] {
        let byPID = Dictionary(nodes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        let children = Dictionary(grouping: nodes, by: \.parent)
        var result: [pid_t: ProcessTreeUsage] = [:]
        for root in roots where byPID[root] != nil {
            var count = 0
            var footprint: UInt64 = 0
            var pending = [root]
            // The listing is not atomic, so a reused pid could close a loop; each process is counted once.
            var seen: Set<pid_t> = []
            while let pid = pending.popLast() {
                guard let node = byPID[pid], seen.insert(pid).inserted else { continue }
                count += 1
                footprint += node.footprint
                pending += children[pid, default: []].map(\.pid)
            }
            result[root] = ProcessTreeUsage(processCount: count, footprint: footprint)
        }
        return result
    }

    private static func node(pid: pid_t) -> ProcessNode? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              let footprint = ProcessList.footprint(pid: pid) else { return nil }
        return ProcessNode(
            pid: pid,
            parent: pid_t(info.pbi_ppid),
            startedAt: Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000),
            footprint: footprint
        )
    }
}

enum ProcessList {
    /// Every pid on the system; reading details of other users' processes fails for them individually.
    static func pids() throws(MetricError) -> [pid_t] {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { throw .systemFailure(code: errno) }
        // Slack for processes started between the two calls.
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 64)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard count > 0 else { throw .systemFailure(code: errno) }
        return pids.prefix(Int(count)).filter { $0 > 0 }
    }

    /// Physical footprint, including compressed and swapped-out pages, like Activity Monitor's "Memory".
    static func footprint(pid: pid_t) -> UInt64? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? info.ri_phys_footprint : nil
    }
}
