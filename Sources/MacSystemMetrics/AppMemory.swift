import Darwin
import Foundation

/// Memory used by one app, its helper processes included.
public struct AppMemoryUsage: Sendable, Equatable, Identifiable {
    /// The outermost app bundle; helper apps nested in it count toward it.
    public let bundlePath: String
    public internal(set) var name: String
    public let processCount: Int
    /// Physical footprint, including compressed and swapped-out pages, like Activity Monitor's "Memory".
    public let footprint: UInt64

    public var id: String { bundlePath }

    /// The outermost `.app` bundle at or above `path`, which may be an executable or a bundle itself
    /// (Docker.app/Contents/MacOS/Docker Desktop.app belongs to Docker.app).
    public static func bundlePath(containing path: String) -> String? {
        let path = path.hasSuffix("/") ? path : path + "/"
        guard let range = path.range(of: ".app/") else { return nil }
        return String(path[..<range.lowerBound]) + ".app"
    }
}

struct ProcessSample: Sendable, Equatable {
    let path: String
    let footprint: UInt64
}

enum AppMemoryAggregator {
    /// Groups processes into the given app bundles; processes outside them are left out.
    static func top(_ samples: [ProcessSample], apps: Set<String>, limit: Int) -> [AppMemoryUsage] {
        var groups: [String: AppMemoryUsage] = [:]
        for sample in samples {
            guard let bundle = AppMemoryUsage.bundlePath(containing: sample.path), apps.contains(bundle) else {
                continue
            }
            let existing = groups[bundle]
            groups[bundle] = AppMemoryUsage(
                bundlePath: bundle,
                name: URL(fileURLWithPath: bundle).deletingPathExtension().lastPathComponent,
                processCount: (existing?.processCount ?? 0) + 1,
                footprint: (existing?.footprint ?? 0) + sample.footprint
            )
        }
        let sorted = groups.values.sorted {
            $0.footprint != $1.footprint ? $0.footprint > $1.footprint : $0.bundlePath < $1.bundlePath
        }
        return Array(sorted.prefix(limit))
    }
}

/// Reads the current user's processes; other users' and root processes need privileges and are skipped.
public final class AppMemoryReader {
    private var appNames: [String: String] = [:]

    public init() {}

    /// The apps in `apps` (outermost bundle paths) using the most memory.
    public func read(apps: Set<String>, limit: Int) throws(MetricError) -> [AppMemoryUsage] {
        AppMemoryAggregator.top(try Self.samples(), apps: apps, limit: limit).map { usage in
            var named = usage
            named.name = appName(usage.bundlePath, fallback: usage.name)
            return named
        }
    }

    /// The name the app declares for itself, localized for the system language, as Activity Monitor
    /// shows it. Cached because it reads the bundle's Info.plist.
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
        var pathBuffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
        return try ProcessList.pids().compactMap { sample(pid: $0, pathBuffer: &pathBuffer) }
    }

    private static func sample(pid: pid_t, pathBuffer buffer: inout [UInt8]) -> ProcessSample? {
        guard let footprint = ProcessList.footprint(pid: pid) else { return nil }
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let path = String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
        return ProcessSample(path: path, footprint: footprint)
    }
}
