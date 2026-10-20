import Foundation

/// A directory and the space it takes on disk.
struct CleanupEntry: Identifiable, Equatable, Sendable {
    let url: URL
    let title: String
    let size: UInt64
    /// The safe location it was found at; only these can be moved to the Trash.
    let location: CleanupScan.Location?

    var id: String { url.path }
    /// What happens after it is removed.
    var note: String? { location?.note }
}

/// How far a scan has got, counted in directories; their sizes are unknown until walked.
struct CleanupProgress: Equatable, Sendable {
    let completed: Int
    let total: Int
    /// The directory being walked.
    let current: String

    var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
}

struct CleanupReport: Equatable, Sendable {
    /// Known tool caches that rebuild themselves; nothing else depends on them.
    let safe: [CleanupEntry]
    /// Other large caches, managed by their apps; shown for reference only.
    let others: [CleanupEntry]
    let scannedAt: Date

    var safeTotal: UInt64 { safe.reduce(0) { $0 + $1.size } }
}

/// Scan of the current user's caches. Only the fixed `safeLocations` can ever be moved to the Trash.
enum CleanupScan {
    struct Location: Equatable, Sendable {
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
    /// Apple's own caches are left out of other caches: some hold protected data (e.g. the media library
    /// under com.apple.Music), and reading them makes the system ask the user for permission.
    static let applePrefix = "com.apple."
    static let othersMinimum: UInt64 = 100_000_000
    static let othersLimit = 8

    /// Walks every listed directory, so it takes seconds; run it off the main thread.
    /// `progress` is called before each directory is walked.
    static func run(
        home: URL,
        size: (URL) -> UInt64 = allocatedSize(of:),
        progress: (CleanupProgress) -> Void = { _ in }
    ) -> CleanupReport {
        let safeURLs = Set(safeLocations.map { home.appending(path: $0.path).standardizedFileURL })
        let safeTargets = safeLocations.compactMap { location -> (Location, URL)? in
            let url = home.appending(path: location.path).standardizedFileURL
            return isDirectory(url) ? (location, url) : nil
        }
        let cachesURL = home.appending(path: othersDirectory)
        let children = (try? FileManager.default.contentsOfDirectory(at: cachesURL, includingPropertiesForKeys: nil)) ?? []
        let otherURLs = children.map(\.standardizedFileURL).filter {
            !$0.lastPathComponent.hasPrefix(applePrefix) && !safeURLs.contains($0) && isDirectory($0)
        }

        // Everything to walk is listed first, so progress has a fixed total.
        let total = safeTargets.count + otherURLs.count
        var completed = 0
        func measure(_ url: URL, as title: String) -> UInt64 {
            progress(CleanupProgress(completed: completed, total: total, current: title))
            completed += 1
            return size(url)
        }
        // Empty locations (e.g. DerivedData without Xcode in use) have nothing to offer.
        let safe = safeTargets.map { location, url in
            CleanupEntry(url: url, title: location.title, size: measure(url, as: location.title), location: location)
        }.filter { $0.size > 0 }
        let others = otherURLs.map { url in
            CleanupEntry(url: url, title: url.lastPathComponent, size: measure(url, as: url.lastPathComponent), location: nil)
        }.filter { $0.size >= othersMinimum }
        return CleanupReport(
            safe: safe.sorted(by: bySize),
            others: Array(others.sorted(by: bySize).prefix(othersLimit)),
            scannedAt: Date()
        )
    }

    /// Moves a safe location to the Trash, where it can be restored; space is freed when the Trash is emptied.
    /// Takes a location rather than a path, so nothing outside the fixed list can be removed.
    static func moveToTrash(_ location: Location, home: URL) throws {
        let url = home.appending(path: location.path).standardizedFileURL
        // Checked again at removal time: the directory may have been replaced since the scan.
        guard isDirectory(url) else { throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: url.path]) }
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
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

/// Holds the latest scan and runs removals; scans run only when asked, never on the refresh clock.
/// The user waits on the result, so it runs at user-initiated priority; utility I/O is throttled to minutes under load.
@MainActor
final class CleanupModel: ObservableObject {
    @Published private(set) var report: CleanupReport?
    @Published private(set) var isScanning = false
    /// Nil until the scan has listed what it will walk.
    @Published private(set) var progress: CleanupProgress?
    /// Why the last removal failed; cleared by the next one.
    @Published private(set) var failure: String?

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        let home = FileManager.default.homeDirectoryForCurrentUser
        // Only the latest position matters; older ones are dropped if the main thread is behind.
        let (updates, continuation) = AsyncStream.makeStream(of: CleanupProgress.self, bufferingPolicy: .bufferingNewest(1))
        let work = Task.detached(priority: .userInitiated) {
            defer { continuation.finish() }
            return CleanupScan.run(home: home, progress: { continuation.yield($0) })
        }
        Task {
            for await update in updates {
                progress = update
            }
            report = await work.value
            progress = nil
            isScanning = false
        }
    }

    /// A same-volume move, so it is quick even for large directories; the rescan then shows what is left.
    func moveToTrash(_ location: CleanupScan.Location) {
        guard !isScanning else { return }
        do {
            try CleanupScan.moveToTrash(location, home: FileManager.default.homeDirectoryForCurrentUser)
            failure = nil
        } catch {
            failure = "未能移走“\(location.title)”：\(error.localizedDescription)"
        }
        scan()
    }

    func scanIfNeeded() {
        if report == nil { scan() }
    }
}
