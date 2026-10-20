import MacStatusCore
import SwiftUI

struct MemorySectionView: View {
    let status: MemoryStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("内存")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PanelStyle.secondaryText)
                MetricStateMark(state: status.displayState)
                Spacer(minLength: 8)
                Text(status.amountText)
                    .font(.system(size: 20, weight: .semibold))
                    .monospacedDigit()
                    .accessibilityLabel(status.accessibilitySummary)
            }

            UsageBar(fraction: status.currentReading?.fraction, tint: pressureTint)

            HStack {
                Text("压力")
                    .accessibilityHidden(true)
                Spacer()
                Text(status.pressureValueText)
                    .accessibilityLabel(status.pressureText)
            }
            .font(.system(size: 11))
            .foregroundStyle(PanelStyle.secondaryText)
        }
    }

    private var pressureTint: Color {
        switch status.currentReading?.pressure {
        case .success(.normal): PanelStyle.accent
        case .success(.warning): .orange
        case .success(.critical): .red
        case .failure, nil: PanelStyle.secondaryText
        }
    }

}
