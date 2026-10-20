import Darwin
import Foundation
import MacStatusCore

public actor SMCTemperatureCollector: TemperatureSampling {
    public init() {}

    public func sample() throws(TemperatureReadError) -> CPUTemperature {
        try CPUTemperatureSensors.requireSupportedModel(Self.readModel())
        let connection = try SMCConnection()
        var values: [Double] = []
        for key in CPUTemperatureSensors.keys {
            values.append(try connection.readTemperature(key: key))
        }
        return CPUTemperature(
            celsius: try CPUTemperatureSensors.maximum(values),
            sampledAt: Date()
        )
    }

    private nonisolated static func readModel() throws(TemperatureReadError) -> String {
        var buffer = [UInt8](repeating: 0, count: 128)
        var size = buffer.count
        let result = buffer.withUnsafeMutableBytes {
            sysctlbyname("hw.model", $0.baseAddress, &size, nil, 0)
        }
        guard result == 0 else { throw .modelReadFailed(code: errno) }
        guard size > 1, size <= buffer.count, buffer[size - 1] == 0 else {
            throw .invalidResponse
        }
        return String(decoding: buffer.prefix(size - 1), as: UTF8.self)
    }
}
