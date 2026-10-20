import AppKit

enum MenuBarMetric: String, CaseIterable {
    case cpu
    case temperature
    case memory
    case disk

    static let defaultSelection: [MenuBarMetric] = [.cpu, .temperature]

    var title: String {
        switch self {
        case .cpu: "CPU 使用率"
        case .temperature: "CPU 温度"
        case .memory: "内存使用率"
        case .disk: "硬盘使用率"
        }
    }

    var symbol: String {
        switch self {
        case .cpu: "cpu"
        case .temperature: "thermometer.medium"
        case .memory: "memorychip"
        case .disk: "internaldrive"
        }
    }

    /// Widest expected text, so the item does not shift as digits change.
    var widthTemplate: String {
        self == .temperature ? "100°" : "100%"
    }

    func text(_ snapshot: MonitorSnapshot) -> String {
        let text: String? = switch self {
        case .cpu: snapshot.cpu.value.map { Format.percent($0.total) }
        case .temperature: snapshot.temperature.value?.cpu.map { "\(Int($0.maximum.rounded()))°" }
        case .memory: snapshot.memory.value.map { Format.percent($0.usedFraction) }
        case .disk: snapshot.disk.value.map { Format.percent($0.usedFraction) }
        }
        return text ?? Format.placeholder
    }
}

/// Draws the status item as one template image so the menu bar tints it for light, dark and highlight.
enum MenuBarRenderer {
    static func image(for items: [(metric: MenuBarMetric, text: String)]) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        let height: CGFloat = 18
        let symbolGap: CGFloat = 3
        let itemGap: CGFloat = 8

        let layouts = items.map { item in
            let symbol = NSImage(systemSymbolName: item.metric.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(symbolConfiguration)
            let text = NSAttributedString(string: item.text, attributes: attributes)
            let slot = max(
                text.size().width,
                NSAttributedString(string: item.metric.widthTemplate, attributes: attributes).size().width
            )
            return (symbol: symbol, text: text, slot: slot)
        }
        let width = layouts.reduce(0) { total, layout in
            total + (layout.symbol.map { $0.size.width + symbolGap } ?? 0) + layout.slot
        } + itemGap * CGFloat(max(layouts.count - 1, 0))

        let image = NSImage(size: NSSize(width: ceil(width), height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for layout in layouts {
                if let symbol = layout.symbol {
                    let size = symbol.size
                    symbol.draw(in: NSRect(x: x, y: (height - size.height) / 2, width: size.width, height: size.height))
                    x += size.width + symbolGap
                }
                layout.text.draw(at: NSPoint(x: x, y: (height - layout.text.size().height) / 2))
                x += layout.slot + itemGap
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
