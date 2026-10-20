public protocol DiskSampling: Sendable {
    func sample() async throws(DiskReadError) -> DiskUsage
}

public enum DiskReadError: Error, Sendable, Equatable {
    case unavailable
    case invalidStatistics
    case timedOut
    case staleReading
}
