import Foundation

enum PanelPlacement {
    static func frame(
        contentSize: NSSize,
        anchor: NSRect,
        screenFrame: NSRect,
        visibleFrame: NSRect,
        menuBarHeight: CGFloat
    ) -> NSRect {
        let width = min(contentSize.width.rounded(.up), visibleFrame.width)
        let height = min(contentSize.height.rounded(.up), visibleFrame.height)
        let top = min(screenFrame.maxY - menuBarHeight, visibleFrame.maxY)
        let x = min(max(anchor.midX - width / 2, visibleFrame.minX), visibleFrame.maxX - width)
        return NSRect(
            x: x,
            y: max(visibleFrame.minY, top - height),
            width: width,
            height: height
        )
    }
}
