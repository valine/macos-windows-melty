import Foundation
import CoreGraphics

public enum Corner: String, CaseIterable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight
    public var left: Bool { self == .topLeft || self == .bottomLeft }
    public var top: Bool { self == .topLeft || self == .topRight }

    /// Hyprland's band is capped at 30%, leaving the center in bottom/right.
    public static func select(at point: CGPoint, in frame: CGRect, band: Double) -> Corner {
        let bx = band > 0 ? min(band, frame.width * 0.30) : frame.width / 2
        let by = band > 0 ? min(band, frame.height * 0.30) : frame.height / 2
        let left = point.x < frame.minX + bx
        let top = point.y < frame.minY + by
        return left ? (top ? .topLeft : .bottomLeft) : (top ? .topRight : .bottomRight)
    }
}

public enum WindowGeometry {
    /// Always solve from the press snapshot: reversal restores geometry and stationary
    /// samples cannot accumulate displacement, including after touching a display wall.
    public static func resize(start: CGRect, delta: CGPoint, corner: Corner, area: CGRect,
                              minimum: CGSize = CGSize(width: 1, height: 1),
                              maximum: CGSize = CGSize(width: Double.greatestFiniteMagnitude,
                                                       height: Double.greatestFiniteMagnitude)) -> CGRect? {
        guard start.width > 0, start.height > 0, area.width > 0, area.height > 0,
              minimum.width <= area.width, minimum.height <= area.height,
              maximum.width >= minimum.width, maximum.height >= minimum.height,
              delta.x.isFinite, delta.y.isFinite else { return nil }
        let x = axis(origin: start.minX, span: start.width, delta: delta.x, low: corner.left,
                     lo: area.minX, hi: area.maxX, minimum: minimum.width, maximum: maximum.width)
        let y = axis(origin: start.minY, span: start.height, delta: delta.y, low: corner.top,
                     lo: area.minY, hi: area.maxY, minimum: minimum.height, maximum: maximum.height)
        return CGRect(x: x.0, y: y.0, width: x.1, height: y.1)
    }

    private static func axis(origin: Double, span: Double, delta: Double, low: Bool,
                             lo: Double, hi: Double, minimum: Double, maximum: Double) -> (Double, Double) {
        let active = (low ? origin : origin + span) + delta
        let wanted = low ? origin + span - active : active - origin
        var size = max(minimum, min(wanted, maximum))
        // Minimum compression pushes the opposite edge; maximum expansion pulls it.
        var position = low ? active : active - size
        if !low && position + size > hi { position = hi - size }
        if low && position < lo { position = lo }
        if position < lo { size -= lo - position; position = lo }
        if position + size > hi { size = hi - position }
        // A constraint can translate the window towards a wall after its span is
        // exhausted. Stop the translation at the wall instead of violating its floor.
        if size < minimum {
            size = minimum
            position = max(lo, min(position, hi - size))
        }
        return (position, size)
    }

    public static func move(start: CGRect, delta: CGPoint, area: CGRect) -> CGRect {
        CGRect(x: start.minX + delta.x, y: max(area.minY, start.minY + delta.y),
               width: start.width, height: start.height)
    }

    /// Shift the entire square inside the window, exactly as Hyprland does.
    public static func sampleRect(at point: CGPoint, frame: CGRect, radius: Int) -> CGRect {
        let side = Double(2 * max(0, min(radius, 64)) + 1)
        let width = min(side, frame.width), height = min(side, frame.height)
        return CGRect(x: max(frame.minX, min(point.x - Double(radius), frame.maxX - width)),
                      y: max(frame.minY, min(point.y - Double(radius), frame.maxY - height)),
                      width: width, height: height)
    }
}

public struct DragIntent: Sendable {
    public let start: CGPoint
    public let threshold: Double
    public private(set) var point: CGPoint
    public private(set) var committed = false
    public init(start: CGPoint, threshold: Double) {
        self.start = start; self.point = start; self.threshold = threshold
    }
    public var delta: CGPoint { CGPoint(x: point.x - start.x, y: point.y - start.y) }
    public mutating func update(_ point: CGPoint) {
        self.point = point
        if hypot(delta.x, delta.y) >= threshold { committed = true }
    }
}

/// Tracks motion beyond a physical display edge without warping the visible cursor.
/// Use global pointer positions in the interior and event deltas only at a clamped edge.
public struct VirtualPointer: Sendable {
    public private(set) var position: CGPoint
    private var lastVisible: CGPoint
    public init(_ point: CGPoint) { position = point; lastVisible = point }
    public mutating func update(visible: CGPoint, relative: CGPoint, display: CGRect) {
        func advance(_ virtual: Double, _ prior: Double, _ current: Double, _ raw: Double,
                     _ lo: Double, _ hi: Double) -> Double {
            let motion = current - prior
            if abs(motion) > 0.001 { return virtual + motion }
            if (current <= lo + 1 && raw < 0) || (current >= hi - 1 && raw > 0) {
                return virtual + raw
            }
            // Some devices deliver relative reversal before the visible cursor moves.
            if (virtual < lo || virtual > hi) && raw != 0 { return virtual + raw }
            return virtual
        }
        position = CGPoint(x: advance(position.x, lastVisible.x, visible.x, relative.x, display.minX, display.maxX),
                           y: advance(position.y, lastVisible.y, visible.y, relative.y, display.minY, display.maxY))
        lastVisible = visible
    }
}
