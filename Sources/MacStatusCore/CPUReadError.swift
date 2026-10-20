public enum CPUReadError: Error, Sendable, Equatable {
    case systemFailure(code: Int32)
    case incompleteSnapshot
    case timedOut
    case staleReading
}
