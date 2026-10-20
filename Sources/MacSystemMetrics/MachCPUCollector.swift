import Darwin
import Foundation
import MacStatusCore

public actor MachCPUCollector: CPUSampling {
    private var previous: CPUTicks?

    public init() {}

    public func reset() {
        previous = nil
    }

    public func sample() throws(CPUReadError) -> CPUUsage? {
        do {
            let ticks = try readTicks()
            defer { previous = ticks }
            guard let previous,
                  let fraction = ticks.busyFraction(since: previous) else { return nil }

            return CPUUsage(
                fraction: fraction,
                sampledAt: Date()
            )
        } catch {
            previous = nil
            throw error
        }
    }

    private func readTicks() throws(CPUReadError) -> CPUTicks {
        var info = host_cpu_load_info_data_t()
        let expectedCount = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size
                / MemoryLayout<integer_t>.stride
        )
        var count = expectedCount
        let host = mach_host_self()
        defer { _ = mach_port_deallocate(mach_task_self_, host) }

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(expectedCount)
            ) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            throw CPUReadError.systemFailure(code: result)
        }
        guard count == expectedCount else {
            throw CPUReadError.incompleteSnapshot
        }

        return CPUTicks(
            user: info.cpu_ticks.0,
            system: info.cpu_ticks.1,
            idle: info.cpu_ticks.2,
            nice: info.cpu_ticks.3
        )
    }
}
