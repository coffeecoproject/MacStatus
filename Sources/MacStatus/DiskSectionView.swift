import MacStatusCore
import SwiftUI

struct DiskSectionView: View {
    let status: DiskStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("硬盘")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PanelStyle.secondaryText)
                MetricStateMark(state: status.displayState)
                Spacer(minLength: 8)
                Text(status.amountText)
                    .font(.system(size: 20, weight: .semibold))
                    .monospacedDigit()
                    .accessibilityLabel(status.accessibilitySummary)
            }

            UsageBar(fraction: status.currentReading?.fraction)
        }
    }
}
