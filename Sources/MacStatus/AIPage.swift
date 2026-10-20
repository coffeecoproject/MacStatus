import AppKit
import SwiftUI

/// Usage limits of the AI coding tools and the Claude Code sessions running now.
struct AIPage: View {
    @ObservedObject var ai: AIModel

    var body: some View {
        // Sessions refresh every two seconds, which also keeps the relative times current.
        let now = Date()
        ListSection(title: "额度") {
            QuotaRow(tool: "Claude Code", state: ai.claude, now: now, retry: ai.retryClaude)
            RowDivider()
            QuotaRow(tool: "Codex", state: ai.codex, now: now, retry: nil)
        } footer: {
            Text("Claude Code 的额度用它在钥匙串中的登录信息查询。")
        }
        ListSection(title: "Claude Code 会话") {
            switch ai.sessions {
            case .loading:
                ListPlaceholder(text: "正在读取…")
            case .unavailable:
                ListPlaceholder(text: "无法读取会话")
            case .ready(let sessions):
                if sessions.isEmpty {
                    ListPlaceholder(text: "没有正在运行的会话")
                }
                ForEach(sessions) { session in
                    if session.id != sessions.first?.id { RowDivider() }
                    SessionRow(session: session, now: now)
                }
            }
        } footer: {
            Text("内存含会话启动的工具与服务进程。")
        }
    }
}

private struct QuotaRow: View {
    let tool: String
    let state: QuotaState
    let now: Date
    /// Nil for tools whose reads need no permission and retry by themselves.
    let retry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(tool).font(.system(size: 12, weight: .medium))
                Spacer(minLength: 8)
                Text(status)
                    .font(.system(size: 10))
                    .foregroundStyle(state.issue == nil ? Color.secondary : .orange)
                    .lineLimit(1)
                if let retry, showsRetry {
                    Button("重试", action: retry)
                        .controlSize(.small)
                        .disabled(state.isUpdating)
                }
            }
            if let reading = state.reading {
                ForEach(reading.windows) { window in
                    WindowBar(window: window, now: now)
                }
                if let credits = reading.credits {
                    Text("另有 \(credits.formatted(.number.precision(.fractionLength(0)))) credits")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .accessibilityElement(children: .contain)
    }

    private var showsRetry: Bool {
        switch state.issue {
        case .denied, .unavailable: true
        case .expired, nil: false
        }
    }

    private var status: String {
        switch state.issue {
        case .expired: return "登录已过期，使用 Claude Code 后更新"
        case .denied: return "未允许读取钥匙串"
        case .unavailable(let reason): return reason
        case nil: break
        }
        guard let reading = state.reading else { return state.isUpdating ? "正在读取…" : Format.placeholder }
        return "\(Format.age(now.timeIntervalSince(reading.reportedAt)))更新"
    }
}

/// One window's share used, and when it resets; a reading taken before the reset no longer applies after it.
private struct WindowBar: View {
    let window: QuotaWindow
    let now: Date

    var body: some View {
        let isReset = window.resetsAt.map { $0 <= now } ?? false
        HStack(spacing: 8) {
            Text(Format.window(minutes: window.minutes))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)
            SegmentedBar(
                segments: isReset ? [] : [.init(id: "used", fraction: window.used, color: tint)],
                height: 4
            )
            Text(isReset ? Format.placeholder : Format.percent(window.used))
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
            Text(isReset ? "已重置" : window.resetsAt.map(resetText) ?? "")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .trailing)
        }
        .font(.system(size: 11))
        .accessibilityElement(children: .combine)
    }

    private var tint: Color {
        window.used >= 0.9 ? .red : window.used >= 0.7 ? .orange : .indigo
    }

    private func resetText(_ date: Date) -> String {
        let sameDay = Calendar.current.isDate(date, inSameDayAs: now)
        let style: Date.FormatStyle = sameDay ? .dateTime.hour().minute() : .dateTime.weekday(.abbreviated).hour().minute()
        return "\(date.formatted(style)) 重置"
    }
}

private struct SessionRow: View {
    let session: AgentSession
    let now: Date
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(session.isBusy ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(session.project) · \(session.isBusy ? "工作中" : "空闲") · \(Format.elapsed(now.timeIntervalSince(session.startedAt)))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if hovering {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([session.directory])
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(.borderless)
                .help("在访达中显示项目")
                .accessibilityLabel("在访达中显示\(session.project)")
            }
            Text(Format.memory(session.usage.footprint))
                .font(.system(size: 12))
                .monospacedDigit()
                .fixedSize()
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(hovering ? Color.primary.opacity(0.04) : .clear)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(session.directory.path)
    }
}
