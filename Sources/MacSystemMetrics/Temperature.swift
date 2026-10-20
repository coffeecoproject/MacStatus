import Foundation

public enum ThermalPressure: Sendable, Equatable {
    case nominal
    case fair
    case serious
    case critical

    init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .critical
        }
    }
}

public struct TemperatureSummary: Sendable, Equatable {
    public let maximum: Double
    public let average: Double
}

public struct TemperatureReading: Sendable, Equatable {
    public let cpu: TemperatureSummary?
    public let gpu: TemperatureSummary?
    public let ssd: Double?
    public let battery: Double?
    public let thermalPressure: ThermalPressure
}

/// SMC sensor groups on Apple Silicon. Keys are discovered at runtime instead of a per-model list.
enum TemperatureSensorGroup: Sendable, Equatable {
    case cpu
    case gpu
    case ssd
    case battery

    init?(key: String) {
        switch key {
        case "TH0x": self = .ssd
        case "TB0T": self = .battery
        case _ where key.hasPrefix("Tp") || key.hasPrefix("Te"): self = .cpu
        case _ where key.hasPrefix("Tg"): self = .gpu
        default: return nil
        }
    }
}

enum TemperatureAggregator {
    /// Idle or unpowered sensors report 0 or sentinel values; they are skipped, not clamped.
    static func isPlausible(_ celsius: Double) -> Bool {
        celsius.isFinite && celsius > 0 && celsius < 150
    }

    static func reading(
        _ samples: [(group: TemperatureSensorGroup, celsius: Double)], thermal: ThermalPressure
    ) -> TemperatureReading? {
        let valid = samples.filter { isPlausible($0.celsius) }
        func values(_ group: TemperatureSensorGroup) -> [Double] {
            valid.filter { $0.group == group }.map(\.celsius)
        }
        let cpu = summary(values(.cpu))
        let gpu = summary(values(.gpu))
        guard cpu != nil || gpu != nil else { return nil }
        return TemperatureReading(
            cpu: cpu, gpu: gpu,
            ssd: values(.ssd).first, battery: values(.battery).first,
            thermalPressure: thermal
        )
    }

    static func summary(_ values: [Double]) -> TemperatureSummary? {
        guard let maximum = values.max() else { return nil }
        return TemperatureSummary(maximum: maximum, average: values.reduce(0, +) / Double(values.count))
    }
}

public final class TemperatureReader {
    private var connection: SMCConnection?
    private var sensors: [(key: String, group: TemperatureSensorGroup)]?

    public init() {}

    public func read() throws(MetricError) -> TemperatureReading {
        #if !arch(arm64)
        throw .unavailable
        #else
        let connection: SMCConnection
        let sensors: [(key: String, group: TemperatureSensorGroup)]
        do throws(MetricError) {
            if let existing = self.connection {
                connection = existing
            } else {
                connection = try SMCConnection()
            }
            if let discovered = self.sensors {
                sensors = discovered
            } else {
                sensors = try Self.discover(connection)
            }
        } catch {
            self.connection = nil
            self.sensors = nil
            throw error
        }
        self.connection = connection
        self.sensors = sensors

        var samples: [(group: TemperatureSensorGroup, celsius: Double)] = []
        for sensor in sensors {
            // A single sensor may be momentarily unreadable; the group summary skips it.
            if let celsius = try? connection.float(for: sensor.key) {
                samples.append((sensor.group, celsius))
            }
        }
        let thermal = ThermalPressure(ProcessInfo.processInfo.thermalState)
        guard let reading = TemperatureAggregator.reading(samples, thermal: thermal) else {
            // Every read failing points at a broken connection; keep the discovered keys.
            if samples.isEmpty, !sensors.isEmpty { self.connection = nil }
            throw .unavailable
        }
        return reading
        #endif
    }

    private static func discover(
        _ smc: SMCConnection
    ) throws(MetricError) -> [(key: String, group: TemperatureSensorGroup)] {
        var sensors: [(key: String, group: TemperatureSensorGroup)] = []
        for index in 0..<(try smc.keyCount()) {
            let key = try smc.key(at: index)
            guard let group = TemperatureSensorGroup(key: key),
                  let info = try? smc.info(for: key),
                  info.size == 4, info.type == SMCMessage.floatType else { continue }
            sensors.append((key, group))
        }
        return sensors
    }
}
