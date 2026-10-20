import Foundation
import MacStatusCore

public actor StartupDiskCollector: DiskSampling {
    private let url: URL

    public init(url: URL = URL(fileURLWithPath: "/")) {
        self.url = url
    }

    public func sample() throws(DiskReadError) -> DiskUsage {
        let values: URLResourceValues
        do {
            values = try url.resourceValues(forKeys: [
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
        guard total > 0, available >= 0, available <= total else {
            throw .invalidStatistics
        }

        return DiskUsage(
            usedBytes: UInt64(total - available),
            totalBytes: UInt64(total),
            sampledAt: Date()
        )
    }
}
