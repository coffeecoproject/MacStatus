import AppKit
import SwiftUI

enum PanelPage: Hashable {
    case overview
    case memory
    case cleanup
}

/// Panel UI state the controller observes to resize the panel and tell the monitor what to sample.
@MainActor
final class PanelModel: ObservableObject {
    @Published var page = PanelPage.overview
    /// Laid-out height of the content, whatever changed it (data, page, a section folding).
    @Published var contentHeight: CGFloat = 0
}

struct StatusPanelView: View {
    @ObservedObject var monitor: SystemMonitor
    @ObservedObject var model: PanelModel
    let cleanup: CleanupModel

    var body: some View {
        let snapshot = monitor.snapshot
        VStack(spacing: 8) {
            Picker("页面", selection: $model.page) {
                Text("概览").tag(PanelPage.overview)
                Text("内存").tag(PanelPage.memory)
                Text("清理").tag(PanelPage.cleanup)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            switch model.page {
            case .overview:
                CPUCard(state: snapshot.cpu, history: snapshot.history.cpu)
                TemperatureCard(state: snapshot.temperature, history: snapshot.history.temperature)
                MemoryCard(state: snapshot.memory)
                DiskCard(
                    state: snapshot.disk,
                    readHistory: snapshot.history.diskRead,
                    writeHistory: snapshot.history.diskWrite
                )
                NetworkCard(
                    state: snapshot.network,
                    downloadHistory: snapshot.history.download,
                    uploadHistory: snapshot.history.upload
                )
            case .memory:
                MemoryPage(memory: snapshot.memory, apps: snapshot.apps)
            case .cleanup:
                CleanupPage(disk: snapshot.disk, cleanup: cleanup)
            }
            footer(updatedAt: snapshot.updatedAt)
        }
        .padding(10)
        .frame(width: 340)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.contentHeight = $0 }
    }

    private func footer(updatedAt: Date?) -> some View {
        HStack {
            if let updatedAt {
                Text("更新于 \(updatedAt.formatted(.dateTime.hour().minute().second()))")
                    .monospacedDigit()
            }
            Spacer()
            Button("退出 MacStatus") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }
}
