import CoreGraphics
import Testing
@testable import WindowBehavior

@Suite struct NativeResizeRouteTests {
    let frame = CGRect(x: 100, y: 100, width: 500, height: 400)
    let area = CGRect(x: 0, y: 25, width: 1000, height: 800)
    @Test func beginsAtCornerThenUsesTotalDisplacement() {
        for corner in Corner.allCases {
            var route = NativeResizeRoute(start: frame, corner: corner)
            let delta = CGPoint(x: 20, y: -30)
            #expect(!route.started)
            #expect(route.nextPoint(delta: delta) == route.anchor)
            #expect(route.started)
            #expect(route.nextPoint(delta: delta) == CGPoint(x: route.anchor.x + 20, y: route.anchor.y - 30))
            #expect(route.nextPoint(delta: .zero) == route.anchor)
        }
    }
    @Test func allDisplayCollisionsHandoff() {
        #expect(NativeResizeRoute(start: frame, corner: .topLeft).needsPush(delta: CGPoint(x: -101, y: 0), area: area))
        #expect(NativeResizeRoute(start: frame, corner: .topLeft).needsPush(delta: CGPoint(x: 0, y: -76), area: area))
        #expect(NativeResizeRoute(start: frame, corner: .bottomRight).needsPush(delta: CGPoint(x: 401, y: 0), area: area))
        #expect(NativeResizeRoute(start: frame, corner: .bottomRight).needsPush(delta: CGPoint(x: 0, y: 326), area: area))
        #expect(!NativeResizeRoute(start: frame, corner: .bottomRight).needsPush(delta: CGPoint(x: 400, y: 325), area: area))
    }
    @Test func crossingOppositeEdgeUsesPushSolver() {
        #expect(NativeResizeRoute(start: frame, corner: .topLeft).needsPush(delta: CGPoint(x: 500, y: 0), area: area))
        #expect(NativeResizeRoute(start: frame, corner: .bottomRight).needsPush(delta: CGPoint(x: 0, y: -400), area: area))
    }
    @Test func negativeOriginDisplayAndOutOfBoundsWindow() {
        let screen = CGRect(x: -1200, y: -500, width: 1200, height: 900)
        let window = CGRect(x: -1100, y: -400, width: 700, height: 500)
        let route = NativeResizeRoute(start: window, corner: .topRight)
        #expect(!route.needsPush(delta: CGPoint(x: 10, y: -10), area: screen))
        #expect(route.needsPush(delta: CGPoint(x: 401, y: 0), area: screen))
        #expect(route.needsPush(delta: .zero, area: area))
    }
}
