import Darwin
import Foundation

/// Memory used by one app (its helpers included) or by one standalone process.
public struct ProcessMemoryUsage: Sendable, Equatable, Identifiable {
    /// The app bundle path, or "pid:<n>" for a process outside any app bundle.
    public let id: String
    public internal(set) var name: String
    public let bundlePath: String?
    public let processCount: Int
    /// Physical footprint, including compressed and swapped-out pages, like Activity Monitor's "Memory".
    public let footprint: UInt64
}

struct ProcessSample: Sendable, Equatable {
    let pid: pid_t
    let name: String
    let path: String?
    let footprint: UInt64
}

enum ProcessMemoryAggregator {
    /// The outermost `.app` bundle containing the executable, so helper apps count toward their host app.
    static func bundlePath(forExecutable path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }

    static func top(_ samples: [ProcessSample], limit: Int) -> [ProcessMemoryUsage] {
        var groups: [String: ProcessMemoryUsage] = [:]
        for sample in samples {
            let bundle = sample.path.flatMap(bundlePath(forExecutable:))
            let id = bundle ?? "pid:\(sample.pid)"
            let existing = groups[id]
            groups[id] = ProcessMemoryUsage(
                id: id,
                name: bundle.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent }
                    ?? sample.name,
                bundlePath: bundle,
                processCount: (existing?.processCount ?? 0) + 1,
                footprint: (existing?.footprint ?? 0) + sample.footprint
            )
        }
        let sorted = groups.values.sorted {
            $0.footprint != $1.footprint ? $0.footprint > $1.footprint : $0.id < $1.id
        }
        return Array(sorted.prefix(limit))
    }
}

/// Reads the current user's processes; other users' and root processes need privileges and are skipped.
public final class ProcessMemoryReader {
    private var appNames: [String: String] = [:]

    public init() {}

    public func read(limit: Int) throws(MetricError) -> [ProcessMemoryUsage] {
        ProcessMemoryAggregator.top(try Self.samples(), limit: limit).map { usage in
            guard let bundle = usage.bundlePath else { return usage }
            var named = usage
            named.name = appName(bundle, fallback: usage.name)
            return named
        }
    }

    /// The name the app declares for itself, localized for the system language, as Activity Monitor
    /// shows it (e.g. "Claude Code" for claude.app). Cached because it reads the bundle's Info.plist.
    private func appName(_ bundle: String, fallback: String) -> String {
        if let cached = appNames[bundle] { return cached }
        // `object(forInfoDictionaryKey:)` prefers the localized value when the bundle has one.
        let info = Bundle(path: bundle)
        let name = ["CFBundleDisplayName", "CFBundleName"].lazy
            .compactMap { info?.object(forInfoDictionaryKey: $0) as? String }
            .first { !$0.isEmpty } ?? fallback
        appNames[bundle] = name
        return name
    }

    private static func samples() throws(MetricError) -> [ProcessSample] {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { throw .systemFailure(code: errno) }
        // Slack for processes started between the two calls.
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 64)
        let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard count > 0 else { throw .systemFailure(code: errno) }
        var pathBuffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        return pids.prefix(Int(count)).compactMap { sample(pid: $0, pathBuffer: &pathBuffer) }
    }

    private static func sample(pid: pid_t, pathBuffer buffer: inout [UInt8]) -> ProcessSample? {
        guard pid > 0 else { return nil }
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard result == 0 else { return nil }

        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        let path = length > 0 ? String(decoding: buffer.prefix(Int(length)), as: UTF8.self) : nil
        let name: String
        if let path {
            name = URL(fileURLWithPath: path).lastPathComponent
        } else {
            var short = [UInt8](repeating: 0, count: 64)
            let shortLength = proc_name(pid, &short, UInt32(short.count))
            name = shortLength > 0 ? String(decoding: short.prefix(Int(shortLength)), as: UTF8.self) : "\(pid)"
        }
        return ProcessSample(pid: pid, name: name, path: path, footprint: info.ri_phys_footprint)
    }
}
