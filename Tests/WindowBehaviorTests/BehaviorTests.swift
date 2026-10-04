import Testing
import CoreGraphics
@testable import WindowBehavior

struct BehaviorTests {
    let area = CGRect(x: 0, y: 30, width: 1000, height: 770)
    let start = CGRect(x: 200, y: 150, width: 400, height: 300)

    @Test func testDockOverlayDoesNotRejectEveryWindow() {
        // Recorded failure: macOS Dock has an opaque-listed full-display surface
        // on layer 20 ahead of the ordinary AX window. It is not an input target.
        let frame = CGRect(x: 300, y: 836, width: 850, height: 592)
        let point = CGPoint(x: 878, y: 1225)
        let sample = WindowGeometry.sampleRect(at: point, frame: frame, radius: 52)
        let dock = WindowRecord(id: 1, pid: 683, layer: 20, alpha: 1, frame: CGRect(x: 0, y: 0, width: 6144, height: 1728))
        let target = WindowRecord(id: 2, pid: 5662, layer: 0, alpha: 1, frame: frame)
        let result = WindowStack.match([dock, target], pid: 5662, frame: frame, point: point, sample: sample)
        #expect(result?.id == 2)
        #expect(result?.unobscured == true)
        let otherApp = WindowRecord(id: 3, pid: 7000, layer: 0, alpha: 1, frame: frame)
        #expect(WindowStack.match([otherApp, target], pid: 5662, frame: frame, point: point, sample: sample) == nil)
    }

    @Test func testNearbyAppWindowCanObscureTheSampleWithoutCoveringThePress() {
        let point = CGPoint(x: 400, y: 300)
        let sample = WindowGeometry.sampleRect(at: point, frame: start, radius: 52)
        let neighbor = WindowRecord(id: 1, pid: 3, layer: 0, alpha: 1, frame: CGRect(x: 440, y: 280, width: 300, height: 200))
        let target = WindowRecord(id: 2, pid: 2, layer: 0, alpha: 1, frame: start)
        let result = WindowStack.match([neighbor, target], pid: 2, frame: start, point: point, sample: sample)
        #expect(result?.id == 2)
        #expect(result?.unobscured == false)
    }

    @Test func testHyprlandCornerBandsDoNotStealTheCenter() {
        #expect(Corner.select(at: CGPoint(x: 250, y: 190), in: start, band: 400) == .topLeft)
        #expect(Corner.select(at: CGPoint(x: 500, y: 190), in: start, band: 400) == .topRight)
        #expect(Corner.select(at: CGPoint(x: 250, y: 300), in: start, band: 400) == .bottomLeft)
        #expect(Corner.select(at: CGPoint(x: 400, y: 300), in: start, band: 400) == .bottomRight)
        // Exactly at the 30% boundary belongs to the bottom/right side.
        #expect(Corner.select(at: CGPoint(x: 320, y: 240), in: start, band: 400) == .bottomRight)
        #expect(Corner.select(at: CGPoint(x: 350, y: 260), in: start, band: 0) == .topLeft)
    }

    @Test func testBottomRightHitsWallThenExpandsOppositeEdgesAndReverses() {
        let before = WindowGeometry.resize(start: start, delta: CGPoint(x: 100, y: 100), corner: .bottomRight, area: area)!
        #expect(before == CGRect(x: 200, y: 150, width: 500, height: 400))
        let wall = WindowGeometry.resize(start: start, delta: CGPoint(x: 500, y: 400), corner: .bottomRight, area: area)!
        #expect(wall == CGRect(x: 100, y: 100, width: 900, height: 700))
        #expect(WindowGeometry.resize(start: start, delta: CGPoint(x: 100, y: 100), corner: .bottomRight, area: area) == before)
        #expect(WindowGeometry.resize(start: start, delta: .zero, corner: .bottomRight, area: area) == start)
        for _ in 0..<100 {
            #expect(WindowGeometry.resize(start: start, delta: CGPoint(x: 500, y: 400), corner: .bottomRight, area: area) == wall)
        }
    }

    @Test func testTopLeftAndAllFourWalls() {
        #expect(WindowGeometry.resize(start: start, delta: CGPoint(x: -300, y: -200), corner: .topLeft, area: area) == CGRect(x: 0, y: 30, width: 700, height: 500))
        for corner in Corner.allCases {
            let delta = CGPoint(x: corner.left ? -2000 : 2000, y: corner.top ? -2000 : 2000)
            #expect(WindowGeometry.resize(start: start, delta: delta, corner: corner, area: area) == area)
        }
    }

    @Test func testMinimumPushesAndMaximumPulls() {
        let minimum = CGSize(width: 300, height: 200)
        let compressed = WindowGeometry.resize(start: start, delta: CGPoint(x: -150, y: -150), corner: .bottomRight, area: area, minimum: minimum)!
        #expect(compressed == CGRect(x: 150, y: 100, width: 300, height: 200))
        let maximum = CGSize(width: 450, height: 350)
        let expanded = WindowGeometry.resize(start: start, delta: CGPoint(x: 100, y: 100), corner: .bottomRight, area: area, maximum: maximum)!
        #expect(expanded == CGRect(x: 250, y: 200, width: 450, height: 350))
        #expect(WindowGeometry.resize(start: start, delta: .zero, corner: .bottomRight, area: area,
                                          minimum: CGSize(width: 1200, height: 300)) == nil)
    }

    @Test func testMoveOnlyClampsTop() {
        #expect(WindowGeometry.move(start: start, delta: CGPoint(x: -800, y: -800), area: area) == CGRect(x: -600, y: 30, width: 400, height: 300))
        #expect(WindowGeometry.move(start: start, delta: CGPoint(x: 1000, y: 1000), area: area) == CGRect(x: 1200, y: 1150, width: 400, height: 300))
    }

    @Test func testSampleSquareShiftsInsideWindowAndShrinksForTinyWindows() {
        #expect(WindowGeometry.sampleRect(at: CGPoint(x: 205, y: 160), frame: start, radius: 52) == CGRect(x: 200, y: 150, width: 105, height: 105))
        let tiny = CGRect(x: -50, y: 20, width: 20, height: 30)
        #expect(WindowGeometry.sampleRect(at: CGPoint(x: -45, y: 25), frame: tiny, radius: 52) == tiny)
    }

    @Test func testUniformityChecksEveryPixelAgainstPressPixelIncludingAlphaAndPadding() {
        var pixels: [UInt8] = [100, 100, 100, 255, 129, 100, 100, 255, 0, 0, 0, 0,
                               100, 100, 100, 255, 100, 100, 100, 255, 0, 0, 0, 0]
        func check(_ bytes: [UInt8]) -> Bool {
            UniformPixels.check(bytes, width: 2, height: 2, rowBytes: 12, referenceX: 0, referenceY: 1, tolerance: 29)
        }
        #expect(check(pixels))
        pixels[4] = 130
        #expect(!(check(pixels)))
        pixels[4] = 100; pixels[19] = 0
        #expect(!(check(pixels)))
        #expect(!(check(Array(repeating: 0, count: 24))))
        #expect(!(check([1, 2, 3])))
    }

    @Test func testThresholdStaysCommittedEvenAfterReversal() {
        var intent = DragIntent(start: CGPoint(x: 100, y: 100), threshold: 8)
        intent.update(CGPoint(x: 104, y: 104))
        #expect(!(intent.committed))
        intent.update(CGPoint(x: 108, y: 100))
        #expect(intent.committed)
        intent.update(CGPoint(x: 100, y: 100))
        #expect(intent.committed)
        #expect(intent.delta == .zero)
    }

    @Test func testPointerContinuesWithoutCursorWarpAndReverses() {
        let display = CGRect(x: -1000, y: 0, width: 1000, height: 800)
        var pointer = VirtualPointer(CGPoint(x: -5, y: 300))
        pointer.update(visible: CGPoint(x: -1, y: 300), relative: CGPoint(x: 4, y: 0), display: display)
        pointer.update(visible: CGPoint(x: -1, y: 300), relative: CGPoint(x: 20, y: 0), display: display)
        #expect(pointer.position.x == 19)
        pointer.update(visible: CGPoint(x: -6, y: 300), relative: CGPoint(x: -5, y: 0), display: display)
        #expect(pointer.position.x == 14)
    }

    @Test func testResizeInvariantsAcrossNegativeOriginDisplay() {
        let area = CGRect(x: -1200, y: -800, width: 1200, height: 800)
        let start = CGRect(x: -900, y: -600, width: 500, height: 350)
        for corner in Corner.allCases {
            for x in stride(from: -1800, through: 1800, by: 83) {
                for y in stride(from: -1200, through: 1200, by: 137) {
                    let result = WindowGeometry.resize(start: start, delta: CGPoint(x: x, y: y), corner: corner, area: area,
                                                       minimum: CGSize(width: 160, height: 120))!
                    #expect(result.width >= 160)
                    #expect(result.height >= 120)
                    #expect(area.contains(result))
                }
            }
        }
    }
}
