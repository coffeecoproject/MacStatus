import Darwin
import Foundation
import MacStatusCore
import MacSystemMetrics
import Testing

@Suite(.serialized)
struct MachCPUCollectorTests {
    @Test func firstReadAndResetRequireANewBaseline() async throws {
        let collector = MachCPUCollector()
        #expect(try await collector.sample() == nil)

        let before = Date()
        let reading = try await nextLiveReading(from: collector)
        #expect(reading.fraction.isFinite)
        #expect((0...1).contains(reading.fraction))
        #expect(reading.sampledAt >= before)
        #expect(reading.sampledAt <= Date())

        await collector.reset()
        #expect(try await collector.sample() == nil)
        _ = try await nextLiveReading(from: collector)
    }

    @Test func successiveLiveSamplesAreBoundedAndTimestamped() async throws {
        let collector = MachCPUCollector()
        _ = try await collector.sample()
        var lastTime = Date()

        for _ in 0..<5 {
            let reading = try await nextLiveReading(from: collector)
            #expect(reading.fraction.isFinite)
            #expect((0...1).contains(reading.fraction))
            #expect(reading.sampledAt >= lastTime)
            lastTime = reading.sampledAt
        }
    }

    @Test func samplingDoesNotAccumulateHostPortSendRights() async throws {
        let collector = MachCPUCollector()
        let host = mach_host_self()
        defer { _ = mach_port_deallocate(mach_task_self_, host) }

        let before = try sendRightCount(for: host)
        for _ in 0..<100 {
            _ = try await collector.sample()
        }
        let after = try sendRightCount(for: host)
        // Leave room for unrelated framework activity in the test process.
        #expect(after <= before + 2)
    }

    private func sendRightCount(for port: mach_port_t) throws -> mach_port_urefs_t {
        var count: mach_port_urefs_t = 0
        let result = mach_port_get_refs(
            mach_task_self_, port, mach_port_right_t(MACH_PORT_RIGHT_SEND), &count
        )
        try #require(result == KERN_SUCCESS)
        return count
    }

    private func nextLiveReading(from collector: MachCPUCollector) async throws -> CPUUsage {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        // The kernel can return identical counters on closely spaced reads.
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(250))
            if let reading = try await collector.sample() {
                return reading
            }
        }
        throw LiveSamplingError.noCounterProgress
    }
}

private enum LiveSamplingError: Error {
    case noCounterProgress
}
