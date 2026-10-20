import Foundation

public struct MemoryUsage: Sendable, Equatable {
    public let usedBytes: UInt64
    public let totalBytes: UInt64
    public let pressure: Result<MemoryPressure, MemoryPressureReadError>
    public let sampledAt: Date

    public var fraction: Double {
        Double(usedBytes) / Double(totalBytes)
    }

    public init(
        usedBytes: UInt64,
        totalBytes: UInt64,
        pressure: Result<MemoryPressure, MemoryPressureReadError>,
        sampledAt: Date
    ) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
        self.pressure = pressure
        self.sampledAt = sampledAt
    }
}

public enum MemoryStatus: Sendable, Equatable {
    case collecting(lastReading: MemoryUsage?)
    case ready(MemoryUsage)
    case unavailable(error: MemoryReadError, lastReading: MemoryUsage?)
    case paused(lastReading: MemoryUsage?)

    public var lastReading: MemoryUsage? {
        switch self {
        case .ready(let reading):
            reading
        case .collecting(let reading),
             .unavailable(_, let reading),
             .paused(let reading):
            reading
        }
    }

    public var currentReading: MemoryUsage? {
        guard case .ready(let reading) = self else { return nil }
        return reading
    }
}
