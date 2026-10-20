public enum MemoryPressure: Sendable, Equatable {
    case normal
    case warning
    case critical
}

public enum MemoryPressureReadError: Error, Sendable, Equatable {
    case systemFailure(code: Int32)
    case incompleteValue
    case unsupportedLevel(Int32)
}
