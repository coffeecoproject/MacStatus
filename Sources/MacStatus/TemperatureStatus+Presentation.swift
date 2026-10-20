import Foundation
import MacStatusCore

extension CPUTemperature {
    var valueText: String {
        "\(celsius.formatted(.number.precision(.fractionLength(0))))°C"
    }
}

extension TemperatureStatus {
    var valueText: String {
        currentReading?.valueText ?? "—"
    }

    var displayState: MetricDisplayState {
        switch self {
        case .collecting: .collecting
        case .ready: .live
        case .unavailable: .unavailable
        case .paused: .paused
        }
    }

    var accessibilitySummary: String {
        if let reading = currentReading {
            return "CPU 温度 \(reading.valueText)"
        }
        return "CPU 温度 \(displayState.title)"
    }
}
