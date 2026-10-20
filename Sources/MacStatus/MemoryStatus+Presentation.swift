import Foundation
import MacStatusCore

extension MemoryUsage {
    var usedAmountText: String {
        (Double(usedBytes) / 1_073_741_824).formatted(.number.precision(.fractionLength(1)))
    }

    var totalAmountText: String {
        (Double(totalBytes) / 1_073_741_824).formatted(.number.precision(.fractionLength(0...1)))
    }

    var amountText: String { "\(usedAmountText) / \(totalAmountText) GiB" }
}

extension MemoryStatus {
    var amountText: String {
        currentReading?.amountText ?? "—"
    }

    var accessibilitySummary: String {
        if let reading = currentReading {
            return "内存已用 \(reading.usedAmountText) GiB，总量 \(reading.totalAmountText) GiB"
        }
        return "内存 \(displayState.title)"
    }

    var displayState: MetricDisplayState {
        switch self {
        case .collecting: .collecting
        case .ready: .live
        case .unavailable: .unavailable
        case .paused: .paused
        }
    }

    var pressureText: String {
        "内存压力：\(pressureValueText)"
    }

    var pressureValueText: String {
        guard let reading = currentReading else { return "—" }
        switch reading.pressure {
        case .success(.normal): return "正常"
        case .success(.warning): return "警告"
        case .success(.critical): return "严重"
        case .failure: return "不可用"
        }
    }
}
