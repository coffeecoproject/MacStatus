import MacSystemMetrics
import SwiftUI

/// Space that known tool caches take, and other large caches for reference. Nothing is removed here.
struct CleanupPage: View {
    let disk: MetricState<DiskReading>
    @ObservedObject var cleanup: CleanupModel

    var body: some View {
        let report = cleanup.report
        MetricCard(
            title: "清理", symbol: "sparkles", tint: .teal,
            value: report.map { Format.disk($0.safeTotal) } ?? Format.placeholder,
            caption: "可安全清理",
            badge: cleanup.isScanning ? MetricBadge(text: "扫描中", color: .secondary) : nil
        ) {
            DetailGrid(items: [
                DetailItem(label: "硬盘可用", value: disk.value.map { Format.disk($0.available) } ?? Format.placeholder),
                DetailItem(
                    label: "扫描于",
                    value: report.map { $0.scannedAt.formatted(.dateTime.hour().minute()) } ?? Format.placeholder
                )
            ])
            if let report {
                section("可安全清理") {
                    if report.safe.isEmpty {
                        Text("没有发现").foregroundStyle(.secondary)
                    }
                    ForEach(report.safe) { CleanupRow(entry: $0) }
                }
                section("其他大缓存 · 由各 App 管理，仅供参考") {
                    if report.others.isEmpty {
                        Text("没有超过 \(Format.disk(CleanupScan.othersMinimum)) 的").foregroundStyle(.secondary)
                    }
                    ForEach(report.others) { CleanupRow(entry: $0) }
                }
            }
            HStack {
                Text("只读扫描，不会改动任何文件。")
                Spacer()
                Button("重新扫描") { cleanup.scan() }
                    .buttonStyle(.borderless)
                    .disabled(cleanup.isScanning)
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
        .onAppear { cleanup.scanIfNeeded() }
    }

    private func section(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            rows()
        }
        .font(.system(size: 11))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CleanupRow: View {
    let entry: CleanupEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let note = entry.note {
                    Text(note)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text(Format.disk(entry.size))
                .monospacedDigit()
                .fixedSize()
        }
        .help(entry.url.path)
    }
}
