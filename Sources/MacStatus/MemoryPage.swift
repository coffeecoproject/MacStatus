import MacSystemMetrics
import SwiftUI

/// Memory, and the quittable apps using the most of it; processes nothing here can act on are not listed.
struct MemoryPage: View {
    let memory: MetricState<MemoryReading>
    let apps: MetricState<[AppMemoryUsage]>

    var body: some View {
        let reading = memory.value
        MetricCard(
            title: "内存", symbol: "memorychip", tint: .green,
            value: reading.map { Format.percent($0.usedFraction) } ?? Format.placeholder,
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
                let shown = listing.shown
                if shown.isEmpty {
                    ListPlaceholder(text: usages.isEmpty ? "没有正在运行的 App" : "没有占用较多内存的 App")
                }
                // The list is sorted, so the first is the largest.
                let largest = shown.first?.footprint
                ForEach(shown) { usage in
                    if usage.id != shown.first?.id { RowDivider() }
                    AppRow(usage: usage, largest: largest)
                }
            }
        } footer: {
            if listing.otherCount > 0 {
                Text("另有 \(listing.otherCount) 个 App 共 \(Format.memory(listing.otherFootprint)) 未列出。")
            }
            Text("按内存占用列出前 \(AppListing.limit) 个，含压缩与交换，不到总内存 1% 的不列出。App 的辅助进程和代它运行的进程（如网页内容、虚拟机、终端里的命令）计入该 App；后台、菜单栏与系统进程不列出。")
        }
    }

    private var listing: AppListing {
        AppListing(apps.value ?? [], total: memory.value?.total)
    }
}

/// The apps worth listing. Quitting one that uses under 1% of physical memory frees too little to matter, and
/// ten rows are enough to find what to quit; the rest are summed up instead of left out without a word.
struct AppListing: Equatable {
    static let limit = 10
    static let minimumShare = 0.01

    let shown: [AppMemoryUsage]
    let otherCount: Int
    let otherFootprint: UInt64

    /// `usages` largest first; with physical memory unknown, only the limit applies.
    init(_ usages: [AppMemoryUsage], total: UInt64?) {
        let minimum = total.map { UInt64(Double($0) * Self.minimumShare) } ?? 0
        shown = Array(usages.prefix { $0.footprint >= minimum }.prefix(Self.limit))
        let others = usages.dropFirst(shown.count)
        otherCount = others.count
        otherFootprint = others.reduce(0) { $0 + $1.footprint }
    }
}

private struct AppRow: View {
    let usage: AppMemoryUsage
    /// The largest app's footprint, which the bar is relative to.
    let largest: UInt64?
    @State private var hovering = false

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
                // Shown for the row under the pointer, so the numbers lead; the space stays to keep the bars aligned.
                .opacity(hovering ? 1 : 0)
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(hovering ? Color.primary.opacity(0.04) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    /// Relative to the largest app, so the bars rank the apps rather than all being slivers of physical memory.
    private var share: Double? {
        guard let largest, largest > 0 else { return nil }
        return Double(usage.footprint) / Double(largest)
    }
}
