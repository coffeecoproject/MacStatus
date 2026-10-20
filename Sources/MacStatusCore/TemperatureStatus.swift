import Foundation

public struct CPUTemperature: Sendable, Equatable {
    public let celsius: Double
    public let sampledAt: Date

    public init(celsius: Double, sampledAt: Date) {
        self.celsius = celsius
        self.sampledAt = sampledAt
    }
}

public enum TemperatureStatus: Sendable, Equatable {
    case collecting(lastReading: CPUTemperature?)
    case ready(CPUTemperature)
    case unavailable(error: TemperatureReadError, lastReading: CPUTemperature?)
    case paused(lastReading: CPUTemperature?)

    public var lastReading: CPUTemperature? {
        switch self {
        case .ready(let reading):
            reading
        case .collecting(let reading),
             .unavailable(_, let reading),
             .paused(let reading):
            reading
        }
    }

    public var currentReading: CPUTemperature? {
        guard case .ready(let reading) = self else { return nil }
        return reading
    }
}
