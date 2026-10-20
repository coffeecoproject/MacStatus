import Foundation
import MacStatusCore
import MacSystemMetrics
import Testing

@Suite(.serialized)
struct StartupDiskCollectorTests {
    @Test func liveSampleContainsRootVolumeUsage() async throws {
        let before = Date()
        let reading = try await StartupDiskCollector().sample()
        #expect(reading.totalBytes > 0)
        #expect(reading.usedBytes <= reading.totalBytes)
        #expect(reading.fraction.isFinite)
        #expect((0...1).contains(reading.fraction))
        #expect(reading.sampledAt >= before)
        #expect(reading.sampledAt <= Date())
    }
}
