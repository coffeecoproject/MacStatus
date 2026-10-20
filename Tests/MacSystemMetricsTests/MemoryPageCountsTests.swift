import MacStatusCore
import Testing
@testable import MacSystemMetrics

struct MemoryPageCountsTests {
    @Test func countsApplicationWiredAndCompressedStorage() throws {
        let pages = MemoryPageCounts(anonymous: 100, purgeable: 20, wired: 30, compressed: 10)
        #expect(try pages.usedBytes(pageSize: 16_384, totalBytes: 8_589_934_592) == 120 * 16_384)
    }

    @Test func doesNotTreatAllNonFreePhysicalMemoryAsUsed() throws {
        let pages = MemoryPageCounts(anonymous: 100, purgeable: 0, wired: 50, compressed: 50)
        // Remaining physical pages can be file cache; they are not added to usage.
        #expect(try pages.usedBytes(pageSize: 4_096, totalBytes: 1_000 * 4_096) == 200 * 4_096)
    }

    @Test func entirelyPurgeableApplicationMemoryIsReclaimable() throws {
        let pages = MemoryPageCounts(anonymous: 100, purgeable: 100, wired: 0, compressed: 0)
        #expect(try pages.usedBytes(pageSize: 16_384, totalBytes: 8_589_934_592) == 0)
    }

    @Test func supportsAnExactlyFullPhysicalMemoryReading() throws {
        let pages = MemoryPageCounts(anonymous: 20, purgeable: 0, wired: 40, compressed: 40)
        #expect(try pages.usedBytes(pageSize: 16_384, totalBytes: 100 * 16_384) == 100 * 16_384)
    }

    @Test(arguments: [
        MemoryPageCounts(anonymous: 1, purgeable: 2, wired: 0, compressed: 0),
        MemoryPageCounts(anonymous: .max, purgeable: 0, wired: 1, compressed: 0),
        MemoryPageCounts(anonymous: 0, purgeable: 0, wired: .max, compressed: 1),
        MemoryPageCounts(anonymous: .max, purgeable: 0, wired: 0, compressed: 0),
        MemoryPageCounts(anonymous: 1_000, purgeable: 0, wired: 0, compressed: 0)
    ])
    func rejectsInconsistentOrOverflowingCounters(pages: MemoryPageCounts) {
        #expect(throws: MemoryReadError.invalidStatistics) {
            try pages.usedBytes(pageSize: 16_384, totalBytes: 100 * 16_384)
        }
    }

    @Test(arguments: [(UInt64(0), UInt64(1_024)), (UInt64(4_096), UInt64(0))])
    func requiresValidPhysicalMemoryMetadata(pageSize: UInt64, total: UInt64) {
        let pages = MemoryPageCounts(anonymous: 0, purgeable: 0, wired: 0, compressed: 0)
        #expect(throws: MemoryReadError.invalidStatistics) {
            try pages.usedBytes(pageSize: pageSize, totalBytes: total)
        }
    }
}
