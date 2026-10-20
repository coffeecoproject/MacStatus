import Foundation
import MacStatusCore

extension CPUUsage {
    var percentageText: String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }
}

extension CPUStatus {
    var percentageText: String {
        currentReading?.percentageText ?? "—"
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
            return "CPU 使用率 \(reading.percentageText)"
        }
        return "CPU \(displayState.title)"
    }
}
