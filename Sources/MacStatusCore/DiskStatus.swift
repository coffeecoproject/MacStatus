import Foundation

public struct DiskUsage: Sendable, Equatable {
    public let usedBytes: UInt64
    public let totalBytes: UInt64
    public let sampledAt: Date

    public var fraction: Double {
        Double(usedBytes) / Double(totalBytes)
    }

    public init(usedBytes: UInt64, totalBytes: UInt64, sampledAt: Date) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
        self.sampledAt = sampledAt
    }
}

public enum DiskStatus: Sendable, Equatable {
    case collecting(lastReading: DiskUsage?)
    case ready(DiskUsage)
    case unavailable(error: DiskReadError, lastReading: DiskUsage?)
    case paused(lastReading: DiskUsage?)

    public var lastReading: DiskUsage? {
        switch self {
        case .ready(let reading):
            reading
        case .collecting(let reading),
             .unavailable(_, let reading),
             .paused(let reading):
            reading
        }
    }

    public var currentReading: DiskUsage? {
        guard case .ready(let reading) = self else { return nil }
        return reading
    }
}
