import Foundation
import MacSystemMetrics

enum Format {
    static let placeholder = "—"

    static func percent(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }

    /// Memory uses binary units, as Activity Monitor does.
    static func memory(_ bytes: UInt64) -> String {
        Int64(bytes).formatted(.byteCount(style: .memory))
    }

    /// Disk uses decimal units, as Finder does.
    static func disk(_ bytes: UInt64) -> String {
        Int64(bytes).formatted(.byteCount(style: .file))
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        Int64(bytesPerSecond.rounded()).formatted(.byteCount(style: .file)) + "/s"
    }

    static func celsius(_ value: Double) -> String {
        "\(Int(value.rounded()))°C"
    }

    static func loadAverage(_ values: [Double]) -> String {
        guard !values.isEmpty else { return placeholder }
        return values.map { $0.formatted(.number.precision(.fractionLength(2))) }.joined(separator: "  ")
    }

    static func pressure(_ pressure: MemoryPressure?) -> String {
        switch pressure {
        case .normal: "正常"
        case .warning: "警告"
        case .critical: "严重"
        case nil: placeholder
        }
    }

    /// Length of a usage-limit window: "5 小时", "7 天".
    static func window(minutes: Int) -> String {
        if minutes % 1440 == 0 { return "\(minutes / 1440) 天" }
        if minutes % 60 == 0 { return "\(minutes / 60) 小时" }
        return "\(minutes) 分钟"
    }

    /// How long something has been running: "3 分钟", "1 小时 55 分".
    static func elapsed(_ interval: TimeInterval) -> String {
        let minutes = max(Int(interval / 60), 0)
        guard minutes >= 60 else { return minutes == 0 ? "不到 1 分钟" : "\(minutes) 分钟" }
        return "\(minutes / 60) 小时 \(minutes % 60) 分"
    }

    /// How long ago something happened: "刚刚", "3 分钟前".
    static func age(_ interval: TimeInterval) -> String {
        let minutes = max(Int(interval / 60), 0)
        if minutes == 0 { return "刚刚" }
        if minutes < 60 { return "\(minutes) 分钟前" }
        if minutes < 1440 { return "\(minutes / 60) 小时前" }
        return "\(minutes / 1440) 天前"
    }

    static func thermal(_ pressure: ThermalPressure) -> String {
        switch pressure {
        case .nominal: "正常"
        case .fair: "偏高"
        case .serious: "过热"
        case .critical: "严重"
        }
    }
}
