import CoreGraphics
import Testing
@testable import WindowBehavior

@Suite struct NativeResizeRouteTests {
    let frame = CGRect(x: 100, y: 100, width: 500, height: 400)
    let area = CGRect(x: 0, y: 25, width: 1000, height: 800)

    @Test func beginsAtCornerThenUsesSelectedEdges() {
        for corner in Corner.allCases {
            var route = NativeResizeRoute(start: frame, corner: corner)
            let desired = WindowGeometry.resize(start: frame, delta: CGPoint(x: 20, y: -30), corner: corner, area: area)!
            #expect(!route.started)
            #expect(route.nextPoint(desired: desired) == route.anchor)
            #expect(route.started)
            #expect(route.nextPoint(desired: desired) == CGPoint(x: route.anchor.x + 20, y: route.anchor.y - 30))
            #expect(route.nextPoint(desired: frame) == route.anchor)
        }
    }

    @Test func allWallsChangeOnlyTheCollidingAxis() {
        #expect(NativeResizeRoute.plan(start: frame, delta: CGPoint(x: -101, y: 0), corner: .topLeft, area: area)?.corner == .topRight)
        #expect(NativeResizeRoute.plan(start: frame, delta: CGPoint(x: 0, y: -76), corner: .topLeft, area: area)?.corner == .bottomLeft)
        #expect(NativeResizeRoute.plan(start: frame, delta: CGPoint(x: 401, y: 0), corner: .bottomRight, area: area)?.corner == .bottomLeft)
        #expect(NativeResizeRoute.plan(start: frame, delta: CGPoint(x: 0, y: 326), corner: .bottomRight, area: area)?.corner == .topRight)
        #expect(NativeResizeRoute.plan(start: frame, delta: CGPoint(x: 401, y: 326), corner: .bottomRight, area: area)?.corner == .topLeft)
        #expect(NativeResizeRoute.plan(start: frame, delta: .zero, corner: .bottomRight, area: area)?.corner == .bottomRight)
    }

    @Test func onlyExtremeCompressionRequiresCompatibility() {
        #expect(NativeResizeRoute.crossesOppositeEdge(start: frame, delta: CGPoint(x: 500, y: 0), corner: .topLeft))
        #expect(NativeResizeRoute.crossesOppositeEdge(start: frame, delta: CGPoint(x: 0, y: -400), corner: .bottomRight))
        #expect(!NativeResizeRoute.crossesOppositeEdge(start: frame, delta: CGPoint(x: 2000, y: 2000), corner: .bottomRight))
    }

    @Test func negativeOriginDisplay() {
        let screen = CGRect(x: -1200, y: -500, width: 1200, height: 900)
        let window = CGRect(x: -1100, y: -400, width: 700, height: 500)
        #expect(NativeResizeRoute.plan(start: window, delta: CGPoint(x: 10, y: -10), corner: .topRight, area: screen)?.corner == .topRight)
        #expect(NativeResizeRoute.plan(start: window, delta: CGPoint(x: 401, y: -101), corner: .topRight, area: screen)?.corner == .bottomLeft)
    }

    // A native backend with discrete row/column sizes, independently fixing the
    // opposite edges just as native AppKit resize does. No position corrections.
    private func draw(_ route: inout NativeResizeRoute, desired: CGRect, step: CGSize) -> CGRect {
        let point = route.nextPoint(desired: desired)
        let dx = point.x - route.anchor.x, dy = point.y - route.anchor.y
        let width = max(step.width, ((route.start.width + (route.corner.left ? -dx : dx)) / step.width).rounded(.down) * step.width)
        let height = max(step.height, ((route.start.height + (route.corner.top ? -dy : dy)) / step.height).rounded(.down) * step.height)
        return CGRect(x: route.corner.left ? route.start.maxX - width : route.start.minX,
                      y: route.corner.top ? route.start.maxY - height : route.start.minY,
                      width: width, height: height)
    }

    @Test(arguments: Corner.allCases)
    func coarseWindowsPushAndReverseWithoutAccumulatingRounding(corner: Corner) {
        let step = CGSize(width: 10, height: 20)
        var route = NativeResizeRoute(start: frame, corner: corner)
        var accepted = frame
        _ = route.nextPoint(desired: frame)
        for _ in 0..<3 {
            // Cross both display boundaries, continue growing, then reverse all
            // the way to the press. Screen height is intentionally off the grid.
            let outward = CGPoint(x: corner.left ? -160 : 460, y: corner.top ? -140 : 390)
            for delta in [outward, CGPoint(x: outward.x * 1.3, y: outward.y * 1.3), outward, .zero] {
                let plan = NativeResizeRoute.plan(start: frame, delta: delta, corner: corner, area: area)!
                if plan.corner != route.corner {
                    accepted = draw(&route, desired: plan.frame, step: step)
                    route = .rebased(accepted: accepted, reference: route.lastReference, corner: plan.corner, originalCorner: corner)
                    _ = route.nextPoint(desired: plan.frame)
                }
                accepted = draw(&route, desired: plan.frame, step: step)
                let held = draw(&route, desired: plan.frame, step: step)
                #expect(held == accepted)
                #expect(accepted.width.truncatingRemainder(dividingBy: 10) == 0)
                #expect(accepted.height.truncatingRemainder(dividingBy: 20) == 0)
            }
            #expect(accepted == frame)
        }
    }
}
