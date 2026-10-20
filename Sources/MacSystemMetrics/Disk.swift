import Foundation
import IOKit

public struct DiskReading: Sendable, Equatable {
    public let name: String
    public let total: UInt64
    /// Available for important usage, i.e. including purgeable space, as Finder reports it.
    public let available: UInt64
    /// Bytes per second across all block storage devices; nil until a baseline exists.
    public let readRate: Double?
    public let writeRate: Double?

    public var used: UInt64 { total - available }
    public var usedFraction: Double { Double(used) / Double(total) }
}

struct DiskIOCounters: Sendable, Equatable {
    var bytesRead: UInt64
    var bytesWritten: UInt64

    /// Nil when counters went backwards (a device detached) or no time elapsed.
    func rates(since previous: DiskIOCounters, elapsed: Double) -> (read: Double, write: Double)? {
        guard elapsed > 0, bytesRead >= previous.bytesRead,
              bytesWritten >= previous.bytesWritten else { return nil }
        return (
            Double(bytesRead - previous.bytesRead) / elapsed,
            Double(bytesWritten - previous.bytesWritten) / elapsed
        )
    }

    static func current() -> DiskIOCounters? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        var counters = DiskIOCounters(bytesRead: 0, bytesWritten: 0)
        var entry = IOIteratorNext(iterator)
        while entry != IO_OBJECT_NULL {
            if let stats = IORegistryEntryCreateCFProperty(
                entry, "Statistics" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? [String: Any] {
                counters.bytesRead += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                counters.bytesWritten += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return counters
    }
}

public final class DiskReader {
    /// Capacity includes purgeable-space accounting, which costs ~10 ms; it changes slowly.
    static let capacityRefresh: Duration = .seconds(10)

    private struct Capacity {
        let name: String
        let total: UInt64
        let available: UInt64
        let readAt: ContinuousClock.Instant
    }

    private let path: String
    private var capacity: Capacity?
    private var io: (counters: DiskIOCounters, at: ContinuousClock.Instant)?

    public init(path: String = "/") {
        self.path = path
    }

    /// Drops the throughput baseline, e.g. after system sleep.
    public func reset() {
        io = nil
    }

    public func read() throws(MetricError) -> DiskReading {
        let now = ContinuousClock.now
        let capacity: Capacity
        if let cached = self.capacity, cached.readAt.duration(to: now) < Self.capacityRefresh {
            capacity = cached
        } else {
            capacity = try readCapacity(at: now)
            self.capacity = capacity
        }

        let counters = DiskIOCounters.current()
        var rates: (read: Double, write: Double)?
        if let counters, let io {
            rates = counters.rates(since: io.counters, elapsed: io.at.duration(to: now).seconds)
        }
        io = counters.map { ($0, now) }

        return DiskReading(
            name: capacity.name,
            total: capacity.total,
            available: capacity.available,
            readRate: rates?.read,
            writeRate: rates?.write
        )
    }

    private func readCapacity(at now: ContinuousClock.Instant) throws(MetricError) -> Capacity {
        // A fresh URL each time: URL caches resource values per instance.
        let url = URL(fileURLWithPath: path)
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [
                .volumeLocalizedNameKey,
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey
            ])
        } catch {
            throw .unavailable
        }
        guard let total = values.volumeTotalCapacity.map(Int64.init),
              let available = values.volumeAvailableCapacityForImportantUsage else {
            throw .unavailable
        }
        guard total > 0, available >= 0, available <= total else { throw .invalidData }
        return Capacity(
            name: values.volumeLocalizedName ?? "",
            total: UInt64(total),
            available: UInt64(available),
            readAt: now
        )
    }
}
