import MacSystemMetrics
import SwiftUI

private func unavailableBadge<Value>(_ state: MetricState<Value>) -> MetricBadge? {
    guard case .unavailable = state else { return nil }
    return MetricBadge(text: "不可用", color: .secondary)
}

struct CPUCard: View {
    let state: MetricState<CPUReading>
    let history: [HistoryPoint]

    var body: some View {
        let reading = state.value
        MetricCard(
            title: "CPU", symbol: "cpu", tint: .blue,
            value: reading.map { Format.percent($0.total) } ?? Format.placeholder,
            badge: unavailableBadge(state)
        ) {
            Sparkline(series: [.init(id: "cpu", points: history, color: .blue)], domain: 0...1)
            CoreBars(cores: reading?.cores ?? [])
            DetailGrid(items: [
                DetailItem(label: "用户", value: reading.map { Format.percent($0.user) } ?? Format.placeholder),
                DetailItem(label: "系统", value: reading.map { Format.percent($0.system) } ?? Format.placeholder),
                DetailItem(label: "负载", value: reading.map { Format.loadAverage($0.loadAverage) } ?? Format.placeholder)
            ])
        }
    }
}

/// Per-core usage, grouped by cluster when the platform reports one.
private struct CoreBars: View {
    let cores: [CPUCoreUsage]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            let groups = groupedCores
            if groups.isEmpty {
                group(title: "核心", cores: [])
            }
            ForEach(groups, id: \.title) { group in
                self.group(title: group.title, cores: group.cores)
            }
        }
    }

    private var groupedCores: [(title: String, cores: [CPUCoreUsage])] {
        [(CPUCoreKind.efficiency, "能效核"), (.performance, "性能核"), (.standard, "核心")].compactMap { kind, title in
            let members = cores.filter { $0.kind == kind }
            return members.isEmpty ? nil : (title, members)
        }
    }

    private func group(title: String, cores: [CPUCoreUsage]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(cores.enumerated()), id: \.offset) { _, core in
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.08))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.blue.opacity(0.85))
                            .frame(height: max(2, 22 * core.usage))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 22)
            HStack {
                Text(title)
                Spacer()
                Text(average(cores).map(Format.percent) ?? Format.placeholder).monospacedDigit()
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private func average(_ cores: [CPUCoreUsage]) -> Double? {
        cores.isEmpty ? nil : cores.map(\.usage).reduce(0, +) / Double(cores.count)
    }
}

struct MemoryCard: View {
    let state: MetricState<MemoryReading>
    let processes: MetricState<[ProcessMemoryUsage]>

    private static let appColor = Color.green
    private static let wiredColor = Color.orange
    private static let compressedColor = Color.purple
    private static let cachedColor = Color.gray.opacity(0.5)

    var body: some View {
        let reading = state.value
        MetricCard(
            title: "内存", symbol: "memorychip", tint: .green,
            value: reading.map { Format.percent($0.usedFraction) } ?? Format.placeholder,
            caption: reading.map { "\(Format.memory($0.used)) / \(Format.memory($0.total))" },
            badge: unavailableBadge(state)
                ?? reading.map { .init(text: "压力 \(Format.pressure($0.pressure))", color: pressureColor($0.pressure)) }
        ) {
            SegmentedBar(segments: segments(reading))
            DetailGrid(items: [
                DetailItem(label: "App", value: amount(reading?.app), color: Self.appColor),
                DetailItem(label: "联动", value: amount(reading?.wired), color: Self.wiredColor),
                DetailItem(label: "压缩", value: amount(reading?.compressed), color: Self.compressedColor),
                DetailItem(label: "缓存", value: amount(reading?.cached), color: Self.cachedColor),
                DetailItem(
                    label: "交换",
                    value: reading?.swap.map { "\(Format.memory($0.used)) / \(Format.memory($0.total))" }
                        ?? Format.placeholder
                )
            ])
            TopProcessList(state: processes, slots: SystemMonitor.processLimit)
        }
    }

    private func segments(_ reading: MemoryReading?) -> [SegmentedBar.Segment] {
        guard let reading else { return [] }
        let total = Double(reading.total)
        return [
            .init(id: "app", fraction: Double(reading.app) / total, color: Self.appColor),
            .init(id: "wired", fraction: Double(reading.wired) / total, color: Self.wiredColor),
            .init(id: "compressed", fraction: Double(reading.compressed) / total, color: Self.compressedColor),
            .init(id: "cached", fraction: Double(reading.cached) / total, color: Self.cachedColor)
        ]
    }

    private func amount(_ bytes: UInt64?) -> String {
        bytes.map(Format.memory) ?? Format.placeholder
    }

    private func pressureColor(_ pressure: MemoryPressure?) -> Color {
        switch pressure {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        case nil: .secondary
        }
    }
}

/// Fixed number of rows, so the panel height measured on open does not change as data arrives.
private struct TopProcessList: View {
    let state: MetricState<[ProcessMemoryUsage]>
    let slots: Int

    var body: some View {
        let usages = state.value ?? []
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("占用最多")
                Spacer()
                Text(isUnavailable ? "不可用" : "含压缩与交换，仅当前用户")
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            ForEach(0..<slots, id: \.self) { index in
                row(index < usages.count ? usages[index] : nil)
            }
        }
        .padding(.top, 2)
    }

    private var isUnavailable: Bool {
        if case .unavailable = state { return true }
        return false
    }

    private func row(_ usage: ProcessMemoryUsage?) -> some View {
        HStack(spacing: 4) {
            Text(usage?.name ?? Format.placeholder)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(usage == nil ? .secondary : .primary)
            if let usage, usage.processCount > 1 {
                Text("\(usage.processCount) 个进程")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
            Spacer(minLength: 8)
            Text(usage.map { Format.memory($0.footprint) } ?? Format.placeholder)
                .monospacedDigit()
                .foregroundStyle(usage == nil ? .secondary : .primary)
                .fixedSize()
            quitButton(usage)
        }
        .font(.system(size: 11))
    }

    /// Fixed-width column, so values stay aligned whether or not a row can be quit.
    private func quitButton(_ usage: ProcessMemoryUsage?) -> some View {
        let apps = usage?.bundlePath.map(QuittableApps.instances(in:)) ?? []
        return ZStack {
            if let usage, !apps.isEmpty {
                Button("退出") { QuittableApps.quit(apps) }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10))
                    .help("退出 \(usage.name)，与在该 App 中选择“退出”相同")
                    .accessibilityLabel("退出 \(usage.name)")
            }
        }
        .frame(width: 26, alignment: .trailing)
    }
}

struct DiskCard: View {
    let state: MetricState<DiskReading>
    let readHistory: [HistoryPoint]
    let writeHistory: [HistoryPoint]

    private static let readColor = Color.teal
    private static let writeColor = Color.pink

    var body: some View {
        let reading = state.value
        MetricCard(
            title: "硬盘", symbol: "internaldrive", tint: .indigo,
            value: reading.map { Format.percent($0.usedFraction) } ?? Format.placeholder,
            caption: reading.map { $0.name.isEmpty ? Format.disk($0.total) : "\($0.name) · \(Format.disk($0.total))" },
            badge: unavailableBadge(state)
        ) {
            SegmentedBar(segments: reading.map {
                [.init(id: "used", fraction: $0.usedFraction, color: .indigo)]
            } ?? [])
            Sparkline(
                series: [
                    .init(id: "read", points: readHistory, color: Self.readColor),
                    .init(id: "write", points: writeHistory, color: Self.writeColor)
                ],
                domain: Sparkline.domain(for: [readHistory, writeHistory], minimum: 1_000_000),
                height: 28
            )
            DetailGrid(items: [
                DetailItem(label: "已用", value: reading.map { Format.disk($0.used) } ?? Format.placeholder),
                DetailItem(label: "可用", value: reading.map { Format.disk($0.available) } ?? Format.placeholder),
                DetailItem(label: "读取", value: reading?.readRate.map(Format.rate) ?? Format.placeholder, color: Self.readColor),
                DetailItem(label: "写入", value: reading?.writeRate.map(Format.rate) ?? Format.placeholder, color: Self.writeColor)
            ])
        }
    }
}

struct TemperatureCard: View {
    let state: MetricState<TemperatureReading>
    let history: [HistoryPoint]

    var body: some View {
        let reading = state.value
        MetricCard(
            title: "温度", symbol: "thermometer.medium", tint: .orange,
            value: reading?.cpu.map { Format.celsius($0.maximum) } ?? Format.placeholder,
            caption: "CPU 最高",
            badge: unavailableBadge(state)
                ?? reading.map { .init(text: "散热 \(Format.thermal($0.thermalPressure))", color: thermalColor($0.thermalPressure)) }
        ) {
            Sparkline(
                series: [.init(id: "temperature", points: history, color: .orange)],
                domain: temperatureDomain
            )
            DetailGrid(items: [
                DetailItem(label: "CPU 平均", value: celsius(reading?.cpu?.average)),
                DetailItem(label: "GPU", value: celsius(reading?.gpu?.maximum)),
                DetailItem(label: "固态硬盘", value: celsius(reading?.ssd)),
                DetailItem(label: "电池", value: celsius(reading?.battery))
            ])
        }
    }

    /// At least a 20°C span, so sensor jitter does not look dramatic.
    private var temperatureDomain: ClosedRange<Double> {
        let values = history.map(\.value)
        let low = (values.min() ?? 40) - 5
        let high = (values.max() ?? 60) + 5
        guard high - low < 20 else { return low...high }
        let middle = (low + high) / 2
        return (middle - 10)...(middle + 10)
    }

    private func celsius(_ value: Double?) -> String {
        value.map(Format.celsius) ?? Format.placeholder
    }

    private func thermalColor(_ pressure: ThermalPressure) -> Color {
        switch pressure {
        case .nominal: .green
        case .fair: .yellow
        case .serious: .orange
        case .critical: .red
        }
    }
}
