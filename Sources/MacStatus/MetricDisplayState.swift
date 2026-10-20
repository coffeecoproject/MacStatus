import SwiftUI

enum MetricDisplayState: Equatable {
    case live
    case collecting
    case unavailable
    case paused

    var title: String {
        switch self {
        case .live: ""
        case .collecting: "采样中"
        case .unavailable: "不可用"
        case .paused: "已暂停"
        }
    }

    var symbol: String? {
        switch self {
        case .live: nil
        case .collecting: "ellipsis"
        case .unavailable: "exclamationmark.circle"
        case .paused: "pause.circle"
        }
    }
}

struct MetricStateMark: View {
    let state: MetricDisplayState

    var body: some View {
        if let symbol = state.symbol {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(PanelStyle.secondaryText)
                .accessibilityLabel(state.title)
        }
    }
}
