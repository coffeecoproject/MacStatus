import MacSystemMetrics
import SwiftUI

/// The quittable apps using the most memory; processes nothing here can act on are not listed.
struct ProcessPage: View {
    let memory: MetricState<MemoryReading>
    let apps: MetricState<[AppMemoryUsage]>

    var body: some View {
        let reading = memory.value
        let usages = apps.value ?? []
        MetricCard(
            title: "进程", symbol: "list.bullet.rectangle", tint: .green,
            value: reading.map { Format.percent($0.usedFraction) } ?? Format.placeholder,
            caption: "按内存占用，含压缩与交换",
            badge: unavailableBadge(apps) ?? reading.map(MemoryCard.pressureBadge)
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
            VStack(spacing: 6) {
                ForEach(usages) { usage in
                    AppRow(usage: usage, total: reading?.total)
                }
            }
            .padding(.top, 2)
            Text("只列可退出的 App（含其辅助进程）；后台、菜单栏、命令行与系统进程不列出。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }
}

private struct AppRow: View {
    let usage: AppMemoryUsage
    /// Physical memory, for the share bar.
    let total: UInt64?

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Text(usage.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if usage.processCount > 1 {
                    Text("\(usage.processCount) 个进程")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
                Spacer(minLength: 8)
                Text(Format.memory(usage.footprint))
                    .monospacedDigit()
                    .fixedSize()
                Button("退出") { QuittableApps.quit(bundlePath: usage.bundlePath) }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10))
                    .help("退出 \(usage.name)，与在该 App 中选择“退出”相同")
                    .accessibilityLabel("退出 \(usage.name)")
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
        guard let total, total > 0 else { return nil }
        return min(Double(usage.footprint) / Double(total), 1)
    }
}
