import Darwin
import Foundation

public enum MemoryPressure: Sendable, Equatable {
    case normal
    case warning
    case critical
}

public struct SwapUsage: Sendable, Equatable {
    public let used: UInt64
    public let total: UInt64
}

/// Byte amounts follow Activity Monitor: used = app + wired + compressed.
public struct MemoryReading: Sendable, Equatable {
    public let total: UInt64
    public let app: UInt64
    public let wired: UInt64
    public let compressed: UInt64
    /// File-backed and purgeable pages the system can reclaim.
    public let cached: UInt64
    public let swap: SwapUsage?
    public let pressure: MemoryPressure?

    public var used: UInt64 { app + wired + compressed }
    public var usedFraction: Double { Double(used) / Double(total) }
}

struct MemoryPageCounts: Sendable {
    let anonymous: UInt64
    let purgeable: UInt64
    let fileBacked: UInt64
    let wired: UInt64
    let compressed: UInt64

    func breakdown(
        pageSize: UInt64, total: UInt64
    ) throws(MetricError) -> (app: UInt64, wired: UInt64, compressed: UInt64, cached: UInt64) {
        guard pageSize > 0, total > 0, purgeable <= anonymous else { throw .invalidData }
        let app = (anonymous - purgeable) * pageSize
        let wired = wired * pageSize
        let compressed = compressed * pageSize
        let cached = (fileBacked + purgeable) * pageSize
        guard app + wired + compressed <= total else { throw .invalidData }
        return (app, wired, compressed, cached)
    }

    static func pressure(level: Int32) -> MemoryPressure? {
        switch level {
        case 1: .normal
        case 2: .warning
        case 4: .critical
        default: nil
        }
    }
}

public final class MemoryReader {
    private let total = ProcessInfo.processInfo.physicalMemory

    public init() {}

    public func read() throws(MetricError) -> MemoryReading {
        let (pages, pageSize) = try Self.statistics()
        let parts = try pages.breakdown(pageSize: pageSize, total: total)
        return MemoryReading(
            total: total,
            app: parts.app,
            wired: parts.wired,
            compressed: parts.compressed,
            cached: parts.cached,
            swap: Self.swapUsage(),
            pressure: Self.pressure()
        )
    }

    private static func statistics() throws(MetricError) -> (MemoryPageCounts, UInt64) {
        var info = vm_statistics64_data_t()
        let expectedCount = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.stride
        )
        var count = expectedCount
        let host = mach_host_self()
        defer { _ = mach_port_deallocate(mach_task_self_, host) }

        var pageSize: vm_size_t = 0
        let pageResult = host_page_size(host, &pageSize)
        guard pageResult == KERN_SUCCESS else { throw .systemFailure(code: pageResult) }

        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(expectedCount)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { throw .systemFailure(code: result) }
        guard count == expectedCount else { throw .invalidData }
        let pages = MemoryPageCounts(
            anonymous: UInt64(info.internal_page_count),
            purgeable: UInt64(info.purgeable_count),
            fileBacked: UInt64(info.external_page_count),
            wired: UInt64(info.wire_count),
            compressed: UInt64(info.compressor_page_count)
        )
        return (pages, UInt64(pageSize))
    }

    private static func swapUsage() -> SwapUsage? {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0,
              size == MemoryLayout<xsw_usage>.size else { return nil }
        return SwapUsage(used: usage.xsu_used, total: usage.xsu_total)
    }

    private static func pressure() -> MemoryPressure? {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0,
              size == MemoryLayout<Int32>.size else { return nil }
        return MemoryPageCounts.pressure(level: level)
    }
}
