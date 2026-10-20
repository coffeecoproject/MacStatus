import Darwin
import Foundation
import MacStatusCore
import MacSystemMetrics
import Testing

@Suite(.serialized)
struct MachMemoryCollectorTests {
    @Test func firstSampleContainsUsageAndTheSystemPressure() async throws {
        let before = Date()
        let reading = try await MachMemoryCollector().sample()
        #expect(reading.totalBytes == ProcessInfo.processInfo.physicalMemory)
        #expect(reading.totalBytes > 0)
        #expect(reading.usedBytes <= reading.totalBytes)
        #expect(reading.fraction.isFinite)
        #expect((0...1).contains(reading.fraction))
        #expect(reading.sampledAt >= before)
        #expect(reading.sampledAt <= Date())
        _ = try reading.pressure.get()
    }

    @Test func samplingDoesNotAccumulateHostPortSendRights() async throws {
        let collector = MachMemoryCollector()
        let host = mach_host_self()
        defer { _ = mach_port_deallocate(mach_task_self_, host) }
        var before: mach_port_urefs_t = 0
        var after: mach_port_urefs_t = 0
        try #require(
            mach_port_get_refs(mach_task_self_, host, mach_port_right_t(MACH_PORT_RIGHT_SEND), &before)
                == KERN_SUCCESS
        )
        for _ in 0..<100 {
            _ = try await collector.sample()
        }
        try #require(
            mach_port_get_refs(mach_task_self_, host, mach_port_right_t(MACH_PORT_RIGHT_SEND), &after)
                == KERN_SUCCESS
        )
        #expect(after <= before + 2)
    }
}
