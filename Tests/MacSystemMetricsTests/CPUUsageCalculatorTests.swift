import Foundation
import Testing
@testable import MacSystemMetrics

struct CPUUsageCalculatorTests {
    private func ticks(_ user: UInt32, _ system: UInt32, _ idle: UInt32, nice: UInt32 = 0) -> CPUTicks {
        CPUTicks(user: user, system: system, idle: idle, nice: nice)
    }

    @Test func aggregatesAllCoresAndKeepsPerCoreUsage() throws {
        let previous = [ticks(0, 0, 0), ticks(0, 0, 0)]
        let current = [ticks(60, 20, 20, nice: 0), ticks(0, 0, 100)]
        let reading = try #require(CPUUsageCalculator.reading(
            current: current, previous: previous,
            kinds: [.efficiency, .performance], loadAverage: [1, 2, 3]
        ))
        #expect(reading.user == 0.3)
        #expect(reading.system == 0.1)
        #expect(abs(reading.total - 0.4) < 1e-9)
        #expect(reading.cores == [
            CPUCoreUsage(kind: .efficiency, usage: 0.8),
            CPUCoreUsage(kind: .performance, usage: 0)
        ])
        #expect(reading.averageUsage(of: .efficiency) == 0.8)
        #expect(reading.averageUsage(of: .standard) == nil)
    }

    @Test func niceTimeCountsAsUserTime() throws {
        let reading = try #require(CPUUsageCalculator.reading(
            current: [ticks(10, 0, 80, nice: 10)], previous: [ticks(0, 0, 0)],
            kinds: [], loadAverage: []
        ))
        #expect(reading.user == 0.2)
        #expect(reading.cores.first?.kind == .standard)
    }

    @Test func wrappedCountersStillProduceDeltas() throws {
        let previous = [ticks(.max - 9, 0, .max - 9)]
        let current = [ticks(10, 0, 10)]
        let reading = try #require(CPUUsageCalculator.reading(
            current: current, previous: previous, kinds: [], loadAverage: []
        ))
        #expect(reading.total == 0.5)
    }

    @Test func noElapsedTimeOrChangedCoreCountYieldsNoReading() {
        let snapshot = [ticks(5, 5, 5)]
        #expect(CPUUsageCalculator.reading(current: snapshot, previous: snapshot, kinds: [], loadAverage: []) == nil)
        #expect(CPUUsageCalculator.reading(
            current: snapshot + snapshot, previous: snapshot, kinds: [], loadAverage: []
        ) == nil)
    }

    @Test func clusterTypeMapsToCoreKind() {
        #expect(CPUTopology.kind(clusterType: Data("P\0".utf8)) == .performance)
        #expect(CPUTopology.kind(clusterType: Data("E\0".utf8)) == .efficiency)
        #expect(CPUTopology.kind(clusterType: Data()) == .standard)
    }
}
