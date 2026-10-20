import MacStatusCore
import SwiftUI

struct TemperatureRowView: View {
    let status: TemperatureStatus

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("CPU 温度")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(PanelStyle.secondaryText)
            MetricStateMark(state: status.displayState)
            Spacer(minLength: 8)
            Text(status.valueText)
                .font(.system(size: 20, weight: .semibold))
                .monospacedDigit()
                .accessibilityLabel(status.accessibilitySummary)
        }
    }
}
