import Darwin
import Foundation
import MacStatusCore

public actor MachMemoryCollector: MemorySampling {
    private let totalBytes = ProcessInfo.processInfo.physicalMemory

    public init() {}

    public func sample() throws(MemoryReadError) -> MemoryUsage {
        let statistics = try readStatistics()
        let usedBytes = try statistics.pages.usedBytes(
            pageSize: statistics.pageSize, totalBytes: totalBytes
        )
        return MemoryUsage(
            usedBytes: usedBytes,
            totalBytes: totalBytes,
            pressure: MemoryPressureReader.read(),
            sampledAt: Date()
        )
    }

    private func readStatistics() throws(MemoryReadError) -> (pages: MemoryPageCounts, pageSize: UInt64) {
        var info = vm_statistics64_data_t()
        let expectedCount = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.stride
        )
        var count = expectedCount
        let host = mach_host_self()
        defer { _ = mach_port_deallocate(mach_task_self_, host) }

        var pageSize: vm_size_t = 0
        let pageResult = host_page_size(host, &pageSize)
        guard pageResult == KERN_SUCCESS else {
            throw .systemFailure(code: pageResult)
        }

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(expectedCount)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            throw .systemFailure(code: result)
        }
        guard count == expectedCount else {
            throw .incompleteSnapshot
        }
        return (
            pages: MemoryPageCounts(
                anonymous: UInt64(info.internal_page_count),
                purgeable: UInt64(info.purgeable_count),
                wired: UInt64(info.wire_count),
                compressed: UInt64(info.compressor_page_count)
            ),
            pageSize: UInt64(pageSize)
        )
    }
}
