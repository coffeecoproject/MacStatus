import Testing
@testable import MacSystemMetrics

struct MemoryBreakdownTests {
    @Test func followsActivityMonitorCategories() throws {
        let pages = MemoryPageCounts(anonymous: 100, purgeable: 20, fileBacked: 50, wired: 30, compressed: 10)
        let parts = try pages.breakdown(pageSize: 16_384, total: 1_000 * 16_384)
        #expect(parts.app == 80 * 16_384)
        #expect(parts.wired == 30 * 16_384)
        #expect(parts.compressed == 10 * 16_384)
        #expect(parts.cached == 70 * 16_384)
    }

    @Test(arguments: [
        MemoryPageCounts(anonymous: 1, purgeable: 2, fileBacked: 0, wired: 0, compressed: 0),
        MemoryPageCounts(anonymous: 50, purgeable: 0, fileBacked: 0, wired: 50, compressed: 1)
    ])
    func inconsistentCountsAreRejected(pages: MemoryPageCounts) {
        #expect(throws: MetricError.invalidData) {
            try pages.breakdown(pageSize: 1, total: 100)
        }
    }

    @Test func pressureLevelsMatchTheKernel() {
        #expect(MemoryPageCounts.pressure(level: 1) == .normal)
        #expect(MemoryPageCounts.pressure(level: 2) == .warning)
        #expect(MemoryPageCounts.pressure(level: 4) == .critical)
        #expect(MemoryPageCounts.pressure(level: 3) == nil)
    }
}
