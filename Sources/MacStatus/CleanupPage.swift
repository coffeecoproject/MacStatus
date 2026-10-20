import AppKit
import MacSystemMetrics
import SwiftUI

/// Space that known tool caches take, which can be moved to the Trash one at a time after confirming,
/// and other large caches for reference only.
struct CleanupPage: View {
    let disk: MetricState<DiskReading>
    @ObservedObject var cleanup: CleanupModel
    /// Other caches can only be looked at, so they stay folded until asked for.
    @State private var showsOthers = false

    var body: some View {
        let report = cleanup.report
        summary(report)
        if let report {
            section("开发工具缓存") {
                if report.safe.isEmpty {
                    placeholder("没有发现可清理的工具缓存")
                }
                rows(report.safe) { entry in
                    CleanupRow(entry: entry, busy: cleanup.isScanning, moveToTrash: entry.location.map { location in
                        { cleanup.moveToTrash(location) }
                    })
                }
            } footer: {
                if let failure = cleanup.failure {
                    Text(failure).foregroundStyle(.red)
                }
                Text("移到废纸篓后可恢复；清空废纸篓才释放空间。")
            }
            othersSection(report.others)
        }
    }

    private func summary(_ report: CleanupReport?) -> some View {
        MetricCard(
            title: "可安全清理", symbol: "sparkles", tint: .teal,
            value: report.map { Format.disk($0.safeTotal) } ?? Format.placeholder,
            caption: "删除后会自动重建，已装内容不受影响"
        ) {
            if cleanup.isScanning {
                ScanProgress(progress: cleanup.progress)
            } else if let reading = disk.value {
                DiskImpact(reading: reading, reclaimable: report?.safeTotal ?? 0)
            }
            HStack {
                Text(report.map { "扫描于 \($0.scannedAt.formatted(.dateTime.hour().minute()))" } ?? "尚未扫描")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("重新扫描") { cleanup.scan() }
                    .controlSize(.small)
                    .disabled(cleanup.isScanning)
            }
        }
        .onAppear { cleanup.scanIfNeeded() }
    }

    private func othersSection(_ others: [CleanupEntry]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                showsOthers.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(showsOthers ? 90 : 0))
                    Text("其他大缓存").font(.system(size: 11, weight: .semibold))
                    Text("由各 App 管理，仅供参考").font(.system(size: 10))
                    Spacer()
                    Text(Format.disk(others.reduce(0) { $0 + $1.size }))
                        .font(.system(size: 11))
                        .monospacedDigit()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showsOthers ? "收起其他大缓存" : "展开其他大缓存")
            if showsOthers {
                card {
                    if others.isEmpty {
                        placeholder("没有超过 \(Format.disk(CleanupScan.othersMinimum)) 的")
                    }
                    rows(others) { CleanupRow(entry: $0, busy: cleanup.isScanning, moveToTrash: nil) }
                }
            }
        }
    }

    private func section(
        _ title: String,
        @ViewBuilder rows: () -> some View,
        @ViewBuilder footer: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            card(rows)
            VStack(alignment: .leading, spacing: 2, content: footer)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 0, content: content)
            .background(Color.primary.opacity(0.05))
            // Row highlights follow the rounded corners.
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Rows separated by inset dividers, as in a grouped list.
    private func rows(_ entries: [CleanupEntry], @ViewBuilder row: @escaping (CleanupEntry) -> some View) -> some View {
        ForEach(entries) { entry in
            if entry.id != entries.first?.id {
                Divider().padding(.leading, 10)
            }
            row(entry)
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
    }
}

/// Disk usage with the reclaimable part marked, and what would be available after emptying the Trash.
private struct DiskImpact: View {
    let reading: DiskReading
    let reclaimable: UInt64

    var body: some View {
        let reclaim = min(reclaimable, reading.used)
        VStack(spacing: 6) {
            SegmentedBar(segments: [
                .init(id: "kept", fraction: Double(reading.used - reclaim) / Double(reading.total), color: .secondary.opacity(0.5)),
                .init(id: "reclaim", fraction: Double(reclaim) / Double(reading.total), color: .teal)
            ])
            DetailGrid(items: [
                DetailItem(label: "硬盘可用", value: Format.disk(reading.available)),
                DetailItem(label: "清理后", value: Format.disk(reading.available + reclaim), color: .teal)
            ])
        }
    }
}

private struct ScanProgress: View {
    let progress: CleanupProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SegmentedBar(segments: [.init(id: "scan", fraction: progress?.fraction ?? 0, color: .teal)], height: 4)
            HStack(spacing: 8) {
                Text(progress.map { "正在扫描 \($0.current)" } ?? "正在列出目录…")
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                if let progress {
                    Text("\(progress.completed) / \(progress.total)")
                        .monospacedDigit()
                        .fixedSize()
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CleanupRow: View {
    let entry: CleanupEntry
    /// Removal is off while a scan is running, since the list may be out of date.
    let busy: Bool
    /// Nil for entries that are only shown.
    let moveToTrash: (() -> Void)?
    /// Removal takes a second click, in place: an alert would take focus and close the panel.
    @State private var confirming = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(size: 12, weight: moveToTrash == nil ? .regular : .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if confirming {
                    Text("移到废纸篓？可恢复")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                } else if let note = entry.note {
                    Text(note)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if hovering, !confirming {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([entry.url])
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("在访达中显示")
                .accessibilityLabel("在访达中显示\(entry.title)")
            }
            Text(Format.disk(entry.size))
                .font(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(moveToTrash == nil ? .secondary : .primary)
                .fixedSize()
            if let moveToTrash {
                if confirming {
                    Button("取消") { confirming = false }
                    Button("移走") {
                        confirming = false
                        moveToTrash()
                    }
                    .tint(.red)
                    .buttonStyle(.borderedProminent)
                    .disabled(busy)
                } else {
                    Button("清理") { confirming = true }
                        .disabled(busy)
                        .accessibilityLabel("清理\(entry.title)")
                }
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, moveToTrash == nil ? 6 : 8)
        .background(confirming ? Color.red.opacity(0.08) : hovering ? Color.primary.opacity(0.04) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(entry.url.path)
    }
}
