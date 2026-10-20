public protocol TemperatureSampling: Sendable {
    func sample() async throws(TemperatureReadError) -> CPUTemperature
}

public enum TemperatureReadError: Error, Sendable, Equatable {
    case unsupportedModel
    case modelReadFailed(code: Int32)
    case serviceUnavailable
    case systemFailure(code: Int32)
    case sensorFailure(key: String, code: UInt8)
    case invalidResponse
    case unsupportedFormat(key: String)
    case invalidValue
    case timedOut
    case staleReading
}
