import Foundation
import Testing
@testable import MacStatus

struct CleanupScanTests {
    private static let megabyte: UInt64 = 1_000_000

    /// A fake home; sizes come from `sizes` by directory name so the test does not depend on block sizes.
    private func scan(
        directories: [String], links: [String: String] = [:], sizes: [String: UInt64]
    ) throws -> CleanupReport {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        for directory in directories {
            try FileManager.default.createDirectory(at: home.appending(path: directory), withIntermediateDirectories: true)
        }
        for (link, target) in links {
            try FileManager.default.createSymbolicLink(at: home.appending(path: link), withDestinationURL: home.appending(path: target))
        }
        return CleanupScan.run(home: home) { sizes[$0.lastPathComponent] ?? 0 }
    }

    @Test func listsOnlyExistingNonEmptySafeLocationsLargestFirst() throws {
        let report = try scan(
            directories: [".npm/_cacache", ".npm/_npx", "Library/Caches/pnpm", "Library/Developer/Xcode/DerivedData"],
            sizes: ["_cacache": 50, "_npx": 900, "pnpm": 80]
        )
        #expect(report.safe.map(\.title) == ["pnpm 缓存", "npm 下载缓存"])
        #expect(report.safe.allSatisfy { $0.note != nil })
        #expect(report.safeTotal == 130)
    }

    @Test func otherCachesExcludeSafeLocationsAndSmallOnes() throws {
        let report = try scan(
            directories: ["Library/Caches/pnpm", "Library/Caches/layermap", "Library/Caches/Google", "Library/Caches/tiny"],
            sizes: [
                "pnpm": 500 * Self.megabyte,
                "layermap": 18_000 * Self.megabyte,
                "Google": 600 * Self.megabyte,
                "tiny": CleanupScan.othersMinimum - 1
            ]
        )
        #expect(report.safe.map(\.title) == ["pnpm 缓存"])
        #expect(report.others.map(\.title) == ["layermap", "Google"])
        #expect(report.others.allSatisfy { $0.note == nil })
    }

    @Test func otherCachesAreCappedAtTheLimit() throws {
        let names = (0..<(CleanupScan.othersLimit + 3)).map { "cache\($0)" }
        let report = try scan(
            directories: names.map { "Library/Caches/\($0)" },
            sizes: Dictionary(uniqueKeysWithValues: names.enumerated().map { ($1, UInt64($0 + 1) * 200 * Self.megabyte) })
        )
        #expect(report.others.count == CleanupScan.othersLimit)
        #expect(report.others.first?.title == names.last)
    }

    @Test func symbolicLinksAreNeverListed() throws {
        let report = try scan(
            directories: ["elsewhere/big", "Library/Caches"],
            links: ["Library/Caches/pnpm": "elsewhere", "Library/Caches/linked": "elsewhere/big"],
            sizes: ["pnpm": 500 * Self.megabyte, "linked": 900 * Self.megabyte]
        )
        #expect(report.safe.isEmpty)
        #expect(report.others.isEmpty)
    }

    @Test func progressCountsEveryWalkedDirectoryInOrder() throws {
        let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        for directory in [".npm/_cacache", "Library/Caches/pnpm", "Library/Caches/layermap", "Library/Caches/empty"] {
            try FileManager.default.createDirectory(at: home.appending(path: directory), withIntermediateDirectories: true)
        }
        var updates: [CleanupProgress] = []
        _ = CleanupScan.run(home: home, size: { _ in 0 }, progress: { updates.append($0) })

        #expect(updates.map(\.completed) == [0, 1, 2, 3])
        #expect(updates.allSatisfy { $0.total == 4 })
        // Safe locations first, by their titles; then other caches by directory name.
        #expect(Array(updates.prefix(2)).map(\.current) == ["npm 下载缓存", "pnpm 缓存"])
        #expect(Set(updates.suffix(2).map(\.current)) == ["layermap", "empty"])
    }

    @Test func missingCachesDirectoryGivesAnEmptyReport() throws {
        let report = try scan(directories: [], sizes: [:])
        #expect(report.safe.isEmpty)
        #expect(report.others.isEmpty)
    }

    @Test func allocatedSizeCountsFilesBelowTheDirectory() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appending(path: "a/b"), withIntermediateDirectories: true)
        try Data(count: 100_000).write(to: root.appending(path: "a/b/file"))
        try Data(count: 50_000).write(to: root.appending(path: "top"))
        #expect(CleanupScan.allocatedSize(of: root) >= 150_000)
        #expect(CleanupScan.allocatedSize(of: root.appending(path: "missing")) == 0)
    }
}
