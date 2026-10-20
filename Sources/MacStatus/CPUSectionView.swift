import MacStatusCore
import SwiftUI

struct CPUSectionView: View {
    let status: CPUStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("CPU")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PanelStyle.secondaryText)
                MetricStateMark(state: status.displayState)
                Spacer(minLength: 8)
                Text(status.percentageText)
                    .font(.system(size: 28, weight: .semibold))
                    .monospacedDigit()
                    .accessibilityLabel(status.accessibilitySummary)
            }

            UsageBar(fraction: status.currentReading?.fraction)
        }
    }
}
