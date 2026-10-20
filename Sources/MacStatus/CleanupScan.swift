import Foundation

/// A directory and the space it takes on disk.
struct CleanupEntry: Identifiable, Equatable, Sendable {
    let url: URL
    let title: String
    /// What happens after it is removed; only safe locations have one.
    let note: String?
    let size: UInt64

    var id: String { url.path }
}

struct CleanupReport: Equatable, Sendable {
    /// Known tool caches that rebuild themselves; nothing else depends on them.
    let safe: [CleanupEntry]
    /// Other large caches, managed by their apps; shown for reference only.
    let others: [CleanupEntry]
    let scannedAt: Date

    var safeTotal: UInt64 { safe.reduce(0) { $0 + $1.size } }
}

/// Read-only scan of the current user's caches. Only the fixed `safeLocations` are ever offered for removal.
enum CleanupScan {
    struct Location: Sendable {
        let title: String
        /// Relative to the home directory.
        let path: String
        let note: String
    }

    static let safeLocations = [
        Location(title: "npm 下载缓存", path: ".npm/_cacache", note: "npm 安装时重新下载"),
        Location(title: "pnpm 缓存", path: "Library/Caches/pnpm", note: "pnpm 安装时重新获取"),
        Location(title: "Homebrew 下载缓存", path: "Library/Caches/Homebrew", note: "已安装的软件不受影响"),
        Location(title: "Playwright 浏览器", path: "Library/Caches/ms-playwright", note: "下次运行前需重新安装浏览器"),
        Location(title: "Xcode 编译缓存", path: "Library/Developer/Xcode/DerivedData", note: "下次编译变慢"),
        Location(title: "iOS 设备支持文件", path: "Library/Developer/Xcode/iOS DeviceSupport", note: "连接设备时重新生成"),
        Location(title: "模拟器缓存", path: "Library/Developer/CoreSimulator/Caches", note: "模拟器启动时重建")
    ]

    static let othersDirectory = "Library/Caches"
    static let othersMinimum: UInt64 = 100_000_000
    static let othersLimit = 8

    /// Walks every listed directory, so it takes seconds; run it off the main thread.
    static func run(home: URL, size: (URL) -> UInt64 = allocatedSize(of:)) -> CleanupReport {
        let safeURLs = Set(safeLocations.map { home.appending(path: $0.path).standardizedFileURL })
        // Empty locations (e.g. DerivedData without Xcode in use) have nothing to offer.
        let safe = safeLocations.compactMap { location -> CleanupEntry? in
            let url = home.appending(path: location.path).standardizedFileURL
            guard isDirectory(url) else { return nil }
            return CleanupEntry(url: url, title: location.title, note: location.note, size: size(url))
        }.filter { $0.size > 0 }
        let cachesURL = home.appending(path: othersDirectory)
        let children = (try? FileManager.default.contentsOfDirectory(at: cachesURL, includingPropertiesForKeys: nil)) ?? []
        let others = children
            .map(\.standardizedFileURL)
            .filter { !safeURLs.contains($0) && isDirectory($0) }
            .map { CleanupEntry(url: $0, title: $0.lastPathComponent, note: nil, size: size($0)) }
            .filter { $0.size >= othersMinimum }
        return CleanupReport(
            safe: safe.sorted(by: bySize),
            others: Array(others.sorted(by: bySize).prefix(othersLimit)),
            scannedAt: Date()
        )
    }

    /// Allocated size of the files under `url`, like `du`; symbolic links are not followed.
    static func allocatedSize(of url: URL) -> UInt64 {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .totalFileAllocatedSizeKey]
        // Unreadable subdirectories are skipped rather than ending the walk.
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(keys), errorHandler: { _, _ in true }
        ) else { return 0 }
        var total: UInt64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += UInt64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    /// A real directory; a symbolic link would point the size, and later the removal, somewhere else.
    private static func isDirectory(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return values?.isDirectory == true && values?.isSymbolicLink != true
    }

    private static func bySize(_ lhs: CleanupEntry, _ rhs: CleanupEntry) -> Bool {
        lhs.size != rhs.size ? lhs.size > rhs.size : lhs.id < rhs.id
    }
}

/// Holds the latest scan; scans run only when asked, never on the refresh clock. The user waits on the
/// result, so it runs at user-initiated priority; utility I/O is throttled to minutes under load.
@MainActor
final class CleanupModel: ObservableObject {
    @Published private(set) var report: CleanupReport?
    @Published private(set) var isScanning = false

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        let home = FileManager.default.homeDirectoryForCurrentUser
        Task {
            report = await Task.detached(priority: .userInitiated) { CleanupScan.run(home: home) }.value
            isScanning = false
        }
    }

    func scanIfNeeded() {
        if report == nil { scan() }
    }
}
