import AppKit
import SwiftUI

struct StatusPanelView: View {
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        let snapshot = monitor.snapshot
        VStack(spacing: 8) {
            CPUCard(state: snapshot.cpu, history: snapshot.history.cpu)
            TemperatureCard(state: snapshot.temperature, history: snapshot.history.temperature)
            MemoryCard(state: snapshot.memory, processes: snapshot.processes)
            DiskCard(
                state: snapshot.disk,
                readHistory: snapshot.history.diskRead,
                writeHistory: snapshot.history.diskWrite
            )
            footer(updatedAt: snapshot.updatedAt)
        }
        .padding(10)
        .frame(width: 340)
        .animation(.easeOut(duration: 0.25), value: snapshot)
    }

    private func footer(updatedAt: Date?) -> some View {
        HStack {
            if let updatedAt {
                Text("更新于 \(updatedAt.formatted(.dateTime.hour().minute().second()))")
                    .monospacedDigit()
            }
            Spacer()
            Button("退出") { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }
}
