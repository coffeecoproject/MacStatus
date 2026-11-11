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

    /// For the menu bar, in decimal units and at most four characters: "0K", "35K", "1.2M", "12M".
    static func compactRate(_ bytesPerSecond: Double) -> String {
        let units = ["K", "M", "G"]
        var value = bytesPerSecond / 1000
        var unit = 0
        while value >= 999.5, unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        // Kilobytes have no decimal: the menu bar has no room, and below 1 MB/s it says little.
        let digits = unit > 0 && value < 9.95
            ? value.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "en_US_POSIX")))
            : "\(Int(value.rounded()))"
        return digits + units[unit]
    }

    /// How long something has been running: "不到 1 分钟", "3 分钟", "1 小时 55 分", "2 天 4 小时".
    static func elapsed(_ interval: TimeInterval) -> String {
        let minutes = max(Int(interval / 60), 0)
        if minutes == 0 { return "不到 1 分钟" }
        if minutes < 60 { return "\(minutes) 分钟" }
        if minutes < 1440 { return "\(minutes / 60) 小时 \(minutes % 60) 分" }
        return "\(minutes / 1440) 天 \(minutes / 60 % 24) 小时"
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

    static func thermal(_ pressure: ThermalPressure) -> String {
        switch pressure {
        case .nominal: "正常"
        case .fair: "偏高"
        case .serious: "过热"
        case .critical: "严重"
        }
    }
}
