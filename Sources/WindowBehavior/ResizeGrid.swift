import Foundation
import CoreGraphics

/// Learn discrete app sizes from accepted values, not from one rejected request.
/// A genuine minimum/maximum supplies only one plateau and cannot establish a grid.
public struct ResizeGrid {
    private struct Axis {
        var samples: [(request: Double, accepted: Double)] = []
        var step = 0.0
        var phase = 0.0
        var rule = FloatingPointRoundingRule.toNearestOrAwayFromZero

        mutating func record(_ requested: Double, _ accepted: Double) {
            guard step == 0, requested.isFinite, accepted.isFinite else { return }
            samples.append((requested, accepted))
            if samples.count > 16 { samples.removeFirst() }
            let values = Set(samples.map { Int($0.accepted.rounded()) }).sorted()
            guard values.count >= 3, samples.filter({ abs($0.request - $0.accepted) > 0.5 }).count >= 2,
                  samples.allSatisfy({ abs($0.accepted - $0.accepted.rounded()) < 0.01 }) else { return }
            func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
            let candidate = zip(values, values.dropFirst()).reduce(0) { gcd($0, $1.1 - $1.0) }
            guard candidate > 1 else { return }
            let spacing = Double(candidate), offset = Double(values[0] % candidate)
            let error = samples.map { abs($0.request - $0.accepted) }.max() ?? 0
            for mode in [FloatingPointRoundingRule.toNearestOrAwayFromZero, .down, .up] {
                // Sparse fast motion can skip several cells. Do not mistake a
                // multiple of the real increment for the app's actual grid.
                let coveredSpacing = mode == .toNearestOrAwayFromZero ? 2 * error + 1 : error + 1
                guard spacing <= coveredSpacing else { continue }
                if samples.allSatisfy({ abs((($0.request - offset) / spacing).rounded(mode) * spacing + offset - $0.accepted) < 0.5 }) {
                    step = spacing; phase = offset; rule = mode
                    return
                }
            }
        }
        func snap(_ value: Double) -> Double {
            step > 0 ? ((value - phase) / step).rounded(rule) * step + phase : value
        }
        func ceiling(in span: Double) -> Double {
            step > 0 ? ((span - phase) / step).rounded(.down) * step + phase : span
        }
    }
    private var x = Axis(), y = Axis()
    public init() {}
    public var increments: CGSize { CGSize(width: x.step, height: y.step) }
    public mutating func record(requested: CGSize, accepted: CGSize) {
        x.record(requested.width, accepted.width)
        y.record(requested.height, accepted.height)
    }
    public func delta(start: CGRect, raw: CGPoint, corner: Corner) -> CGPoint {
        let width = start.width + (corner.left ? -raw.x : raw.x)
        let height = start.height + (corner.top ? -raw.y : raw.y)
        return CGPoint(x: (x.snap(width) - start.width) * (corner.left ? -1 : 1),
                       y: (y.snap(height) - start.height) * (corner.top ? -1 : 1))
    }
    public func maximum(in area: CGRect) -> CGSize {
        CGSize(width: max(1, x.ceiling(in: area.width)), height: max(1, y.ceiling(in: area.height)))
    }
}
