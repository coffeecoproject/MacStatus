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
