import Darwin
import Foundation
import IOKit

public enum CPUCoreKind: Sendable, Equatable {
    case performance
    case efficiency
    case standard
}

public struct CPUCoreUsage: Sendable, Equatable {
    public let kind: CPUCoreKind
    /// Busy fraction of this core, 0...1.
    public let usage: Double
}

public struct CPUReading: Sendable, Equatable {
    /// Whole-machine user time (including nice) as a fraction of all CPU time, 0...1.
    public let user: Double
    /// Whole-machine system time as a fraction of all CPU time, 0...1.
    public let system: Double
    public let cores: [CPUCoreUsage]
    /// 1, 5 and 15 minute load averages; empty when unavailable.
    public let loadAverage: [Double]

    public var total: Double { user + system }

    public func averageUsage(of kind: CPUCoreKind) -> Double? {
        let values = cores.filter { $0.kind == kind }.map(\.usage)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

struct CPUTicks: Sendable, Equatable {
    let user: UInt32
    let system: UInt32
    let idle: UInt32
    let nice: UInt32
}

enum CPUUsageCalculator {
    /// Returns nil when the snapshots do not describe the same cores or no time elapsed.
    static func reading(
        current: [CPUTicks], previous: [CPUTicks], kinds: [CPUCoreKind], loadAverage: [Double]
    ) -> CPUReading? {
        guard !current.isEmpty, current.count == previous.count else { return nil }
        var user: UInt64 = 0
        var system: UInt64 = 0
        var total: UInt64 = 0
        var cores: [CPUCoreUsage] = []
        for index in current.indices {
            let now = current[index]
            let before = previous[index]
            // Mach's cumulative 32-bit counters can wrap on long uptimes.
            let coreUser = UInt64(now.user &- before.user) + UInt64(now.nice &- before.nice)
            let coreSystem = UInt64(now.system &- before.system)
            let coreTotal = coreUser + coreSystem + UInt64(now.idle &- before.idle)
            user += coreUser
            system += coreSystem
            total += coreTotal
            cores.append(CPUCoreUsage(
                kind: index < kinds.count ? kinds[index] : .standard,
                usage: coreTotal == 0 ? 0 : Double(coreUser + coreSystem) / Double(coreTotal)
            ))
        }
        guard total > 0 else { return nil }
        return CPUReading(
            user: Double(user) / Double(total),
            system: Double(system) / Double(total),
            cores: cores,
            loadAverage: loadAverage
        )
    }
}

public final class CPUReader {
    private let kinds = CPUTopology.coreKinds()
    private var previous: [CPUTicks]?

    public init() {}

    /// Drops the baseline, e.g. after system sleep.
    public func reset() {
        previous = nil
    }

    /// Returns nil until a baseline from the previous call exists.
    public func read() throws(MetricError) -> CPUReading? {
        let ticks: [CPUTicks]
        do {
            ticks = try Self.readTicks()
        } catch {
            previous = nil
            throw error
        }
        defer { previous = ticks }
        guard let previous else { return nil }
        return CPUUsageCalculator.reading(
            current: ticks, previous: previous, kinds: kinds, loadAverage: Self.loadAverage()
        )
    }

    private static func readTicks() throws(MetricError) -> [CPUTicks] {
        var processorCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let host = mach_host_self()
        defer { _ = mach_port_deallocate(mach_task_self_, host) }

        let result = host_processor_info(host, PROCESSOR_CPU_LOAD_INFO, &processorCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { throw .systemFailure(code: result) }
        defer {
            _ = vm_deallocate(
                mach_task_self_, vm_address_t(bitPattern: info),
                vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)
            )
        }
        let states = Int(CPU_STATE_MAX)
        guard processorCount > 0, Int(infoCount) == Int(processorCount) * states else {
            throw .invalidData
        }
        return (0..<Int(processorCount)).map { core in
            let base = core * states
            return CPUTicks(
                user: UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]),
                system: UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]),
                idle: UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]),
                nice: UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            )
        }
    }

    private static func loadAverage() -> [Double] {
        var values = [Double](repeating: 0, count: 3)
        return getloadavg(&values, 3) == 3 ? values : []
    }
}

enum CPUTopology {
    /// Core kinds indexed by logical CPU id, from the IORegistry `cluster-type` property.
    /// Empty when the platform does not describe clusters (e.g. Intel).
    static func coreKinds() -> [CPUCoreKind] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("IOPlatformDevice"), &iterator
        ) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }

        var kinds: [Int: CPUCoreKind] = [:]
        var entry = IOIteratorNext(iterator)
        while entry != IO_OBJECT_NULL {
            if let id = property(entry, "logical-cpu-id") as? Int,
               let cluster = property(entry, "cluster-type") as? Data {
                kinds[id] = kind(clusterType: cluster)
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        guard !kinds.isEmpty, kinds.keys.sorted() == Array(0..<kinds.count) else { return [] }
        return (0..<kinds.count).map { kinds[$0]! }
    }

    static func kind(clusterType: Data) -> CPUCoreKind {
        switch clusterType.first {
        case UInt8(ascii: "P"): .performance
        case UInt8(ascii: "E"): .efficiency
        default: .standard
        }
    }

    private static func property(_ entry: io_registry_entry_t, _ name: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, name as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
    }
}
