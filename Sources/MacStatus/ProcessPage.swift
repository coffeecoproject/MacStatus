import MacSystemMetrics
import SwiftUI

/// Apps and processes using the most memory, with a normal quit for regular apps.
struct ProcessPage: View {
    let memory: MetricState<MemoryReading>
    let processes: MetricState<[ProcessMemoryUsage]>

    var body: some View {
        let reading = memory.value
        let usages = processes.value ?? []
        MetricCard(
            title: "进程", symbol: "list.bullet.rectangle", tint: .green,
            value: reading.map { Format.percent($0.usedFraction) } ?? Format.placeholder,
            caption: "按内存占用，含压缩与交换",
            badge: unavailableBadge(processes) ?? reading.map(MemoryCard.pressureBadge)
        ) {
            DetailGrid(items: [
                DetailItem(
                    label: "已用",
                    value: reading.map { "\(Format.memory($0.used)) / \(Format.memory($0.total))" } ?? Format.placeholder
                ),
                DetailItem(
                    label: "交换",
                    value: reading?.swap.map { "\(Format.memory($0.used)) / \(Format.memory($0.total))" }
                        ?? Format.placeholder
                )
            ])
            // Fixed number of rows, so the panel height measured on open does not change as data arrives.
            VStack(spacing: 6) {
                ForEach(0..<SystemMonitor.processLimit, id: \.self) { index in
                    ProcessRow(usage: index < usages.count ? usages[index] : nil, total: reading?.total)
                }
            }
            .padding(.top, 2)
            Text("仅当前用户的进程；“退出”等同在该 App 中选择“退出”。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

private struct ProcessRow: View {
    let usage: ProcessMemoryUsage?
    /// Physical memory, for the share bar.
    let total: UInt64?

    var body: some View {
        VStack(spacing: 3) {
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
                quitButton
            }
            .font(.system(size: 11))
            SegmentedBar(
                segments: share.map { [.init(id: "share", fraction: $0, color: .green.opacity(0.7))] } ?? [],
                height: 3
            )
        }
    }

    /// Footprint includes swapped-out pages, so it can exceed physical memory; the bar is capped.
    private var share: Double? {
        guard let usage, let total, total > 0 else { return nil }
        return min(Double(usage.footprint) / Double(total), 1)
    }

    /// Fixed-width column, so values stay aligned whether or not a row can be quit.
    private var quitButton: some View {
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
