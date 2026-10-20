import Foundation

public struct CPUUsage: Sendable, Equatable {
    /// Whole-machine busy time as a fraction of total CPU time, from 0 to 1.
    public let fraction: Double
    public let sampledAt: Date

    public init(fraction: Double, sampledAt: Date) {
        self.fraction = fraction
        self.sampledAt = sampledAt
    }
}

public enum CPUStatus: Sendable, Equatable {
    case collecting(lastReading: CPUUsage?)
    case ready(CPUUsage)
    case unavailable(error: CPUReadError, lastReading: CPUUsage?)
    case paused(lastReading: CPUUsage?)

    public var lastReading: CPUUsage? {
        switch self {
        case .ready(let reading):
            reading
        case .collecting(let reading),
             .unavailable(_, let reading),
             .paused(let reading):
            reading
        }
    }

    public var currentReading: CPUUsage? {
        guard case .ready(let reading) = self else { return nil }
        return reading
    }
}
