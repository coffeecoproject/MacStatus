import Testing
@testable import MacSystemMetrics

struct CPUTicksTests {
    private let zero = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)

    @Test(arguments: [
        (CPUTicks(user: 0, system: 0, idle: 100, nice: 0), 0.0),
        (CPUTicks(user: 100, system: 0, idle: 0, nice: 0), 1.0),
        (CPUTicks(user: 0, system: 100, idle: 0, nice: 0), 1.0),
        (CPUTicks(user: 0, system: 0, idle: 0, nice: 100), 1.0),
        (CPUTicks(user: 30, system: 15, idle: 50, nice: 5), 0.5),
        (CPUTicks(user: 100, system: 100, idle: 100, nice: 100), 0.75)
    ])
    func computesExactBusyFractions(ticks: CPUTicks, expected: Double) {
        #expect(ticks.busyFraction(since: zero) == expected)
    }

    @Test func usesTheIntervalRatherThanLifetimeTotals() throws {
        let previous = CPUTicks(user: 100, system: 200, idle: 300, nice: 400)
        let current = CPUTicks(user: 110, system: 220, idle: 370, nice: 400)
        let fraction = try #require(current.busyFraction(since: previous))
        #expect(abs(fraction - 0.3) < 1e-12)
    }

    @Test func unchangedCountersDoNotInventZeroUsage() {
        let ticks = CPUTicks(user: 10, system: 20, idle: 30, nice: 40)
        #expect(ticks.busyFraction(since: ticks) == nil)
        #expect(zero.busyFraction(since: zero) == nil)
    }

    @Test func eachCounterCanWrapIndependently() throws {
        let previous = CPUTicks(user: .max - 9, system: 0, idle: 10, nice: 0)
        let current = CPUTicks(user: 10, system: 0, idle: 50, nice: 0)
        let fraction = try #require(current.busyFraction(since: previous))
        #expect(abs(fraction - 1.0 / 3.0) < 1e-12)
    }

    @Test func handlesAllCountersWrapping() throws {
        let previous = CPUTicks(
            user: .max - 9, system: .max - 19, idle: .max - 29, nice: .max - 4
        )
        let current = CPUTicks(user: 10, system: 10, idle: 10, nice: 5)
        let fraction = try #require(current.busyFraction(since: previous))
        #expect(abs(fraction - 0.6) < 1e-12)
    }

    @Test func summingLargeDeltasDoesNotOverflow32Bits() {
        let current = CPUTicks(user: .max, system: .max, idle: .max, nice: .max)
        #expect(current.busyFraction(since: zero) == 0.75)
    }
}
