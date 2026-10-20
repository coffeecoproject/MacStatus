public enum MetricError: Error, Sendable, Equatable {
    case systemFailure(code: Int32)
    case invalidData
    case unavailable
}

extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
