import SwiftUI

struct StatusPanelView: View {
    @ObservedObject var monitor: SystemMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CPUSectionView(status: monitor.snapshot.cpu)
            TemperatureRowView(status: monitor.snapshot.temperature)
            separator
            MemorySectionView(status: monitor.snapshot.memory)
            separator
            DiskSectionView(status: monitor.snapshot.disk)
        }
        .padding(16)
        .frame(width: 280)
        .foregroundStyle(PanelStyle.primaryText)
        .background(PanelStyle.background)
        .clipShape(RoundedRectangle(cornerRadius: PanelStyle.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: PanelStyle.cornerRadius, style: .continuous)
                .strokeBorder(PanelStyle.secondaryText.opacity(0.2), lineWidth: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .preferredColorScheme(.dark)
    }

    private var separator: some View {
        Rectangle()
            .fill(PanelStyle.secondaryText.opacity(0.2))
            .frame(height: 1)
            .accessibilityHidden(true)
    }
}
