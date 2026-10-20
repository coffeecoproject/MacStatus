import Testing
@testable import MacSystemMetrics

struct DiskIOCountersTests {
    @Test func ratesAreBytesPerSecond() throws {
        let previous = DiskIOCounters(bytesRead: 1_000, bytesWritten: 500)
        let current = DiskIOCounters(bytesRead: 5_000, bytesWritten: 2_500)
        let rates = try #require(current.rates(since: previous, elapsed: 2))
        #expect(rates.read == 2_000)
        #expect(rates.write == 1_000)
    }

    @Test func detachedDeviceOrZeroIntervalYieldsNoRate() {
        let previous = DiskIOCounters(bytesRead: 5_000, bytesWritten: 500)
        #expect(DiskIOCounters(bytesRead: 1_000, bytesWritten: 600).rates(since: previous, elapsed: 1) == nil)
        #expect(previous.rates(since: previous, elapsed: 0) == nil)
    }
}
