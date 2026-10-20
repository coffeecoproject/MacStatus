import Foundation
import Testing
@testable import MacSystemMetrics

struct SMCTemperatureCollectorTests {
    @Test func liveSamplesArePlausibleAndTimestampedWithoutElevatedPrivileges() async throws {
        let collector = SMCTemperatureCollector()
        let started = Date()
        let first = try await collector.sample()
        #expect(first.celsius > 0 && first.celsius < 150)
        #expect(first.sampledAt >= started)
        for _ in 0..<8 {
            let next = try await collector.sample()
            #expect(next.celsius > 0 && next.celsius < 150)
            #expect(next.sampledAt >= first.sampledAt)
        }
    }
}
