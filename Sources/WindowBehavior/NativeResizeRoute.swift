import CoreGraphics

/// Geometry for forwarding a gesture through macOS's real resize hit region.
/// WindowServer owns geometry until a display collision needs our push solver.
public struct NativeResizeRoute {
    public let start: CGRect
    public let corner: Corner
    public let anchor: CGPoint
    public private(set) var started = false
    public private(set) var lastPoint: CGPoint

    public init(start: CGRect, corner: Corner) {
        self.start = start
        self.corner = corner
        // A rounded window's mathematical corner can be outside its hit shape.
        let inset = min(5.0, min(start.width, start.height) / 4)
        anchor = CGPoint(x: corner.left ? start.minX + inset : start.maxX - inset,
                         y: corner.top ? start.minY + inset : start.maxY - inset)
        lastPoint = anchor
    }

    public mutating func nextPoint(delta: CGPoint) -> CGPoint {
        if !started {
            started = true
            lastPoint = anchor
        } else {
            lastPoint = CGPoint(x: anchor.x + delta.x, y: anchor.y + delta.y)
        }
        return lastPoint
    }

    public func needsPush(delta: CGPoint, area: CGRect) -> Bool {
        let x = (corner.left ? start.minX : start.maxX) + delta.x
        let y = (corner.top ? start.minY : start.maxY) + delta.y
        // Crossing the opposite edge also requires our minimum-size push logic.
        return !area.contains(start) || x < area.minX || x > area.maxX
            || y < area.minY || y > area.maxY
            || (corner.left ? x >= start.maxX - 1 : x <= start.minX + 1)
            || (corner.top ? y >= start.maxY - 1 : y <= start.minY + 1)
    }
}
