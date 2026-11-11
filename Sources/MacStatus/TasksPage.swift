import MacSystemMetrics
import SwiftUI

/// Commands coding agents are running across their sessions, which may be ended from here after confirming.
struct TasksPage: View {
    let tasks: MetricState<[AgentTask]>

    var body: some View {
        let running = tasks.value ?? []
        ListSection(title: "Claude Code、Codex 会话中运行的命令") {
            switch tasks {
            case .loading:
                ListPlaceholder(text: "正在读取…")
            case .unavailable:
                ListPlaceholder(text: "无法读取进程列表")
            case .ready:
                if running.isEmpty {
                    ListPlaceholder(text: "没有正在运行的命令")
                }
                ForEach(running) { task in
                    if task.id != running.first?.id { RowDivider() }
                    TaskRow(task: task)
                }
            }
        } footer: {
            Text("内存含命令启动的全部进程；“结束”发送正常结束信号，不强制结束。")
        }
    }
}

private struct TaskRow: View {
    let task: AgentTask
    /// Ending takes a second click, in place: an alert would take focus and close the panel.
    @State private var confirming = false
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.headline)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if confirming {
                    Text("结束这个命令及其子进程？")
                        .font(.system(size: 10))
                        .foregroundStyle(.red)
                        .lineLimit(1)
                } else {
                    details
                        .font(.system(size: 10))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if confirming {
                Button("取消") { confirming = false }
                Button("结束") {
                    confirming = false
                    AgentTaskReader.terminate(task)
                }
                .tint(.red)
                .buttonStyle(.borderedProminent)
            } else {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Format.memory(task.footprint))
                        .font(.system(size: 12))
                    Text(Format.elapsed(-task.startedAt.timeIntervalSinceNow))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .monospacedDigit()
                .fixedSize()
                // The button takes the numbers' place under the pointer, leaving the command its width.
                .opacity(hovering ? 0 : 1)
                .overlay(alignment: .trailing) {
                    // Hidden rather than absent, so it stays reachable without a pointer, as in the app list.
                    Button("结束") { confirming = true }
                        .accessibilityLabel("结束 \(task.headline)")
                        .opacity(hovering ? 1 : 0)
                }
            }
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(confirming ? Color.red.opacity(0.08) : hovering ? Color.primary.opacity(0.04) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // Scripts can run to pages; the tooltip shows enough to tell them apart.
        .help(String(task.command.prefix(600)))
    }

    private var details: some View {
        HStack(spacing: 0) {
            Text([task.project, task.agent].compactMap { $0 }.joined(separator: " · "))
                .foregroundStyle(.secondary)
                .truncationMode(.middle)
            // Kept whole when the rest is cut short.
            if task.detached {
                Text(" · 遗留")
                    .foregroundStyle(.orange)
                    .fixedSize()
                    .help("启动它的 shell 已退出，会话不再管理它，它仍在运行。卡住的命令可以结束；有意放在后台的服务（如本地守护进程）不要结束。")
            }
        }
    }
}
