import CoreGraphics

/// One native resize segment. Keep the accepted frame separate from the ideal
/// geometry: a terminal may accept only whole columns/rows. Never compensate for
/// that rounding by moving its opposite edge.
public struct NativeResizeRoute {
    public let start: CGRect
    public let reference: CGRect
    public let corner: Corner
    public let anchor: CGPoint
    public private(set) var started = false
    public private(set) var lastPoint: CGPoint
    public private(set) var lastReference: CGRect

    public init(start: CGRect, corner: Corner, reference: CGRect? = nil) {
        self.start = start
        self.reference = reference ?? start
        self.lastReference = reference ?? start
        self.corner = corner
        let inset = min(5.0, min(start.width, start.height) / 4)
        anchor = CGPoint(x: corner.left ? start.minX + inset : start.maxX - inset,
                         y: corner.top ? start.minY + inset : start.maxY - inset)
        lastPoint = anchor
    }

    public mutating func nextPoint(desired: CGRect) -> CGPoint {
        if !started {
            started = true
            lastPoint = anchor
        } else {
            let x = corner.left ? desired.minX : desired.maxX
            let y = corner.top ? desired.minY : desired.maxY
            lastPoint = CGPoint(x: anchor.x + x - (corner.left ? reference.minX : reference.maxX),
                                y: anchor.y + y - (corner.top ? reference.minY : reference.maxY))
            // Only the active edges moved in this segment. At wall contact the
            // opposite edges still belong to its reference frame.
            let left = corner.left ? x : reference.minX
            let top = corner.top ? y : reference.minY
            let right = corner.left ? reference.maxX : x
            let bottom = corner.top ? reference.maxY : y
            lastReference = CGRect(x: left, y: top, width: right - left, height: bottom - top)
        }
        return lastPoint
    }

    public static func plan(start: CGRect, delta: CGPoint, corner: Corner, area: CGRect) -> (frame: CGRect, corner: Corner)? {
        guard let frame = WindowGeometry.resize(start: start, delta: delta, corner: corner, area: area) else { return nil }
        let x = (corner.left ? start.minX : start.maxX) + delta.x
        let y = (corner.top ? start.minY : start.maxY) + delta.y
        let left = corner.left ? x >= area.minX : x > area.maxX
        let top = corner.top ? y >= area.minY : y > area.maxY
        return (frame, left ? (top ? .topLeft : .bottomLeft) : (top ? .topRight : .bottomRight))
    }

    public static func crossesOppositeEdge(start: CGRect, delta: CGPoint, corner: Corner) -> Bool {
        let width = start.width + (corner.left ? -delta.x : delta.x)
        let height = start.height + (corner.top ? -delta.y : delta.y)
        return width <= 1 || height <= 1
    }

    public static func rebased(accepted: CGRect, reference: CGRect, corner: Corner,
                               originalCorner: Corner) -> NativeResizeRoute {
        var adjusted = reference
        // On reversal to an original edge, return to absolute pointer geometry.
        // Carrying a wall's fractional cell remainder back would accumulate a
        // column/row of error on every round trip with floor-rounded apps.
        if corner.left == originalCorner.left {
            adjusted.origin.x = accepted.minX
            adjusted.size.width = accepted.width
        }
        if corner.top == originalCorner.top {
            adjusted.origin.y = accepted.minY
            adjusted.size.height = accepted.height
        }
        return NativeResizeRoute(start: accepted, corner: corner, reference: adjusted)
    }
}
