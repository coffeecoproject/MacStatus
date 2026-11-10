import Testing
@testable import MacStatus
@testable import MacSystemMetrics

struct AppListingTests {
    private func usages(_ footprints: [UInt64]) -> [AppMemoryUsage] {
        footprints.enumerated().map {
            AppMemoryUsage(bundlePath: "/Applications/A\($0).app", name: "A\($0)", processCount: 1, footprint: $1)
        }
    }

    @Test func appsUnderOnePercentOfMemoryAreSummedUp() {
        let listing = AppListing(usages([3_000, 100, 99, 10]), total: 10_000)
        #expect(listing.shown.map(\.footprint) == [3_000, 100])
        #expect(listing.otherCount == 2)
        #expect(listing.otherFootprint == 109)
    }

    @Test func listsAtMostTheLimit() {
        let listing = AppListing(usages(Array(repeating: 500, count: AppListing.limit + 2)), total: 10_000)
        #expect(listing.shown.count == AppListing.limit)
        #expect(listing.otherCount == 2)
        #expect(listing.otherFootprint == 1_000)
    }

    @Test func withMemoryUnknownOnlyTheLimitApplies() {
        let listing = AppListing(usages([3_000, 1]), total: nil)
        #expect(listing.shown.count == 2)
        #expect(listing.otherCount == 0)
    }
}
