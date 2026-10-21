import Foundation

struct HistoryPoint: Equatable {
    let time: Date
    let value: Double
}

/// Rolling window of recent values for the panel's sparklines.
struct MetricHistory: Equatable {
    static let window: TimeInterval = 60

    private(set) var cpu: [HistoryPoint] = []
    private(set) var diskRead: [HistoryPoint] = []
    private(set) var diskWrite: [HistoryPoint] = []
    private(set) var temperature: [HistoryPoint] = []

    enum Series {
        case cpu, diskRead, diskWrite, temperature
    }

    mutating func append(_ value: Double, to series: Series, at time: Date) {
        switch series {
        case .cpu: Self.append(value, at: time, to: &cpu)
        case .diskRead: Self.append(value, at: time, to: &diskRead)
        case .diskWrite: Self.append(value, at: time, to: &diskWrite)
        case .temperature: Self.append(value, at: time, to: &temperature)
        }
    }

    /// For a series no longer sampled, so the gap is not drawn as a line across it.
    mutating func clear(_ series: Series) {
        switch series {
        case .cpu: cpu = []
        case .diskRead: diskRead = []
        case .diskWrite: diskWrite = []
        case .temperature: temperature = []
        }
    }

    private static func append(_ value: Double, at time: Date, to points: inout [HistoryPoint]) {
        let cutoff = time.addingTimeInterval(-window)
        points.removeAll { $0.time < cutoff }
        points.append(HistoryPoint(time: time, value: value))
    }
}
