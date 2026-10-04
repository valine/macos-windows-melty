import CoreGraphics

public struct WindowRecord: Sendable {
    public let id: UInt32
    public let pid: Int32
    public let layer: Int
    public let alpha: Double
    public let frame: CGRect
    public init(id: UInt32, pid: Int32, layer: Int, alpha: Double, frame: CGRect) {
        self.id = id; self.pid = pid; self.layer = layer; self.alpha = alpha; self.frame = frame
    }
}

public enum WindowStack {
    /// Accessibility performs the OS hit-test. WindowServer then corroborates the
    /// normal app window and checks whether its sample is overlapped. Noninteractive
    /// system overlays (including the Dock's full-screen layer 20 window) are not
    /// app hit targets, despite preceding the app in WindowServer's list.
    public static func match(_ windows: [WindowRecord], pid: Int32, frame: CGRect,
                             point: CGPoint, sample: CGRect) -> (id: UInt32, unobscured: Bool)? {
        var above: [CGRect] = []
        for window in windows where window.layer == 0 && window.alpha > 0 {
            if !window.frame.contains(point) { above.append(window.frame); continue }
            guard window.pid == pid,
                  abs(window.frame.minX - frame.minX) < 3, abs(window.frame.minY - frame.minY) < 3,
                  abs(window.frame.width - frame.width) < 3, abs(window.frame.height - frame.height) < 3 else { return nil }
            return (window.id, !above.contains { $0.intersects(sample) })
        }
        return nil
    }
}
