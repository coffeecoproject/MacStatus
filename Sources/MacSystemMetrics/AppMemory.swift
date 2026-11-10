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
    /// Executable of the process responsible for this one, when that is another process.
    var responsiblePath: String?
    let footprint: UInt64

    init(path: String, responsiblePath: String? = nil, footprint: UInt64) {
        self.path = path
        self.responsiblePath = responsiblePath
        self.footprint = footprint
    }
}

enum AppMemoryAggregator {
    /// Groups processes into the given app bundles, largest first; processes belonging to none of them are left out.
    static func usages(_ samples: [ProcessSample], apps: Set<String>) -> [AppMemoryUsage] {
        var groups: [String: AppMemoryUsage] = [:]
        for sample in samples {
            guard let bundle = app(of: sample, in: apps) else { continue }
            let existing = groups[bundle]
            groups[bundle] = AppMemoryUsage(
                bundlePath: bundle,
                name: URL(fileURLWithPath: bundle).deletingPathExtension().lastPathComponent,
                processCount: (existing?.processCount ?? 0) + 1,
                footprint: (existing?.footprint ?? 0) + sample.footprint
            )
        }
        return groups.values.sorted {
            $0.footprint != $1.footprint ? $0.footprint > $1.footprint : $0.bundlePath < $1.bundlePath
        }
    }

    /// The app bundle a process runs from, or else the one of the app responsible for it, as Activity Monitor
    /// groups them: Safari's web content and Docker's virtual machine run from system frameworks.
    private static func app(of sample: ProcessSample, in apps: Set<String>) -> String? {
        [sample.path, sample.responsiblePath].lazy
            .compactMap { $0.flatMap(AppMemoryUsage.bundlePath(containing:)) }
            .first(where: apps.contains)
    }
}

/// Reads the current user's processes; other users' and root processes need privileges and are skipped.
public final class AppMemoryReader {
    private var appNames: [String: String] = [:]

    public init() {}

    /// The memory of each running app in `apps` (outermost bundle paths), largest first.
    public func read(apps: Set<String>) throws(MetricError) -> [AppMemoryUsage] {
        AppMemoryAggregator.usages(try Self.samples(), apps: apps).map { usage in
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
        let processes = try ProcessList.pids().compactMap { process(pid: $0, pathBuffer: &pathBuffer) }
        let paths = Dictionary(processes.map { ($0.pid, $0.path) }, uniquingKeysWith: { first, _ in first })
        return processes.map {
            ProcessSample(path: $0.path, responsiblePath: $0.responsible.flatMap { paths[$0] }, footprint: $0.footprint)
        }
    }

    private static func process(
        pid: pid_t, pathBuffer buffer: inout [UInt8]
    ) -> (pid: pid_t, path: String, footprint: UInt64, responsible: pid_t?)? {
        guard let footprint = ProcessList.footprint(pid: pid) else { return nil }
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        let path = String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
        let responsible = (Responsibility.responsiblePID?(pid)).flatMap { $0 > 0 && $0 != pid ? $0 : nil }
        return (pid, path, footprint, responsible)
    }
}

/// Which process macOS holds responsible for another, as privacy prompts and Activity Monitor use it: the app
/// on whose behalf a system XPC service runs, or the terminal a command was started from.
private enum Responsibility {
    typealias Function = @convention(c) (pid_t) -> pid_t

    /// Private but exported by libsystem. Looked up at run time (in every loaded image: `RTLD_DEFAULT`, which
    /// Swift does not import) so that, should a later macOS drop it, the app still launches and processes count
    /// toward the bundle they run from only.
    static let responsiblePID: Function? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid")
        .map { unsafeBitCast($0, to: Function.self) }
}
