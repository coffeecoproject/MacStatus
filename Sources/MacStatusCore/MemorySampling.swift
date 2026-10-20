public protocol MemorySampling: Sendable {
    func sample() async throws(MemoryReadError) -> MemoryUsage
}

public enum MemoryReadError: Error, Sendable, Equatable {
    case systemFailure(code: Int32)
    case incompleteSnapshot
    case invalidStatistics
    case timedOut
    case staleReading
}
