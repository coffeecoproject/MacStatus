import MacSystemMetrics
import SwiftUI

/// The quittable apps using the most memory; processes nothing here can act on are not listed.
struct ProcessPage: View {
    let memory: MetricState<MemoryReading>
    let apps: MetricState<[AppMemoryUsage]>

    var body: some View {
        let reading = memory.value
        MetricCard(
            title: "进程", symbol: "list.bullet.rectangle", tint: .green,
            value: reading.map { Format.percent($0.usedFraction) } ?? Format.placeholder,
            caption: "按内存占用，含压缩与交换",
            badge: unavailableBadge(memory) ?? reading.map(MemoryCard.pressureBadge)
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
        }
        ListSection(title: "可退出的 App") {
            switch apps {
            case .loading:
                ListPlaceholder(text: "正在读取…")
            case .unavailable:
                ListPlaceholder(text: "无法读取 App 列表")
            case .ready(let usages):
                if usages.isEmpty {
                    ListPlaceholder(text: "没有正在运行的 App")
                }
                ForEach(usages) { usage in
                    if usage.id != usages.first?.id { RowDivider() }
                    AppRow(usage: usage, total: reading?.total)
                }
            }
        } footer: {
            Text("含各 App 的辅助进程；后台、菜单栏、命令行与系统进程不列出。")
        }
    }
}

private struct AppRow: View {
    let usage: AppMemoryUsage
    /// Physical memory, for the share bar.
    let total: UInt64?

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(usage.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if usage.processCount > 1 {
                        Text("\(usage.processCount) 个进程")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
                SegmentedBar(
                    segments: share.map { [.init(id: "share", fraction: $0, color: .green.opacity(0.7))] } ?? [],
                    height: 3
                )
            }
            Text(Format.memory(usage.footprint))
                .font(.system(size: 12))
                .monospacedDigit()
                // A fixed column keeps the bars to the left the same length, so they compare.
                .frame(width: 72, alignment: .trailing)
            Button("退出") { QuittableApps.quit(bundlePath: usage.bundlePath) }
                .help("退出 \(usage.name)，与在该 App 中选择“退出”相同")
                .accessibilityLabel("退出 \(usage.name)")
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    /// Footprint includes swapped-out pages, so it can exceed physical memory; the bar is capped.
    private var share: Double? {
        guard let total, total > 0 else { return nil }
        return min(Double(usage.footprint) / Double(total), 1)
    }
}
