import SwiftUI

enum PanelStyle {
    static let cornerRadius: CGFloat = 20
    static let background = Color(red: 0.098, green: 0.176, blue: 0.337)
    static let track = Color(red: 0.125, green: 0.239, blue: 0.451)
    static let accent = Color(red: 0.263, green: 0.561, blue: 0.961)
    static let primaryText = Color(red: 0.961, green: 0.969, blue: 0.988)
    static let secondaryText = Color(red: 0.710, green: 0.765, blue: 0.867)
}

struct UsageBar: View {
    let fraction: Double?
    var tint: Color = PanelStyle.accent

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(PanelStyle.track)
                if let fraction {
                    Capsule()
                        .fill(tint)
                        .frame(width: geometry.size.width * fraction)
                }
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}
