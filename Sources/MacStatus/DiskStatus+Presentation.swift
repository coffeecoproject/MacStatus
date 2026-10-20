import Foundation
import MacStatusCore

extension DiskUsage {
    var usedAmountText: String {
        (Double(usedBytes) / 1_073_741_824).formatted(.number.precision(.fractionLength(0...1)))
    }

    var totalAmountText: String {
        (Double(totalBytes) / 1_073_741_824).formatted(.number.precision(.fractionLength(0...1)))
    }

    var amountText: String { "\(usedAmountText) / \(totalAmountText) GiB" }
}

extension DiskStatus {
    var amountText: String {
        currentReading?.amountText ?? "—"
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
            return "硬盘已用 \(reading.usedAmountText) GiB，总量 \(reading.totalAmountText) GiB"
        }
        return "硬盘 \(displayState.title)"
    }
}
