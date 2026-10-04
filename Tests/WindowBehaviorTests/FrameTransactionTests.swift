import Testing
import CoreGraphics
@testable import WindowBehavior

/// Models a native window whose setters each keep it on the usable display.
/// Size requests are limited by the room at its CURRENT origin, as well as the
/// app's own minimum/maximum. This catches failures the pure geometry tests miss.
private final class DisplayClampedWindow: WindowFrameAccess {
    var frame: CGRect
    let area: CGRect
    var minimum = CGSize(width: 1, height: 1)
    var maximum = CGSize(width: Double.greatestFiniteMagnitude, height: Double.greatestFiniteMagnitude)
    var anchorsSizeAtBottom = false
    var refusesSize = false
    var presentedFrames: [CGRect] = []

    init(frame: CGRect, area: CGRect) { self.frame = frame; self.area = area }
    func readFrame() -> CGRect? { frame }
    func setPosition(_ point: CGPoint) -> Bool {
        frame.origin = CGPoint(x: max(area.minX, min(point.x, area.maxX - frame.width)),
                               y: max(area.minY, min(point.y, area.maxY - frame.height)))
        presentedFrames.append(frame)
        return true
    }
    func setSize(_ size: CGSize) -> Bool {
        guard !refusesSize else { return false }
        let bottom = frame.maxY
        frame.size = CGSize(width: max(minimum.width, min(size.width, maximum.width, area.maxX - frame.minX)),
                            height: max(minimum.height, min(size.height, maximum.height, area.maxY - frame.minY)))
        if anchorsSizeAtBottom { frame.origin.y = bottom - frame.height }
        presentedFrames.append(frame)
        return true
    }
}

struct FrameTransactionTests {
    let area = CGRect(x: 0, y: 30, width: 1000, height: 770)
    let start = CGRect(x: 200, y: 150, width: 400, height: 300)

    @Test func ordinaryDiagonalResizeDoesNotPresentAnIntermediateShape() throws {
        let window = DisplayClampedWindow(frame: start, area: area)
        let desired = CGRect(x: 200, y: 150, width: 500, height: 250)
        #expect(try FrameTransaction.resize(start: start, delta: CGPoint(x: 100, y: -50),
                                            corner: .bottomRight, area: area, using: window) == desired)
        // Previously this displayed a shorter old-width window, moved it to the
        // same position, then widened it: three redraws for one pointer sample.
        #expect(window.presentedFrames == [desired])
    }

    @Test func fractionalPointerSamplesDoNotRepeatNativeFrameWrites() throws {
        let window = DisplayClampedWindow(frame: start, area: area)
        for fraction in [0.05, 0.1, 0.2, 0.4] {
            try FrameTransaction.resize(start: start, delta: CGPoint(x: 10 + fraction, y: 20 + fraction),
                                        corner: .bottomRight, area: area, using: window)
        }
        #expect(window.presentedFrames == [CGRect(x: 200, y: 150, width: 410, height: 320)])
    }

    @Test func bottomPushOnlyMakesTheRequiredMoveAndResize() throws {
        let window = DisplayClampedWindow(frame: start, area: area)
        try FrameTransaction.resize(start: start, delta: CGPoint(x: 0, y: 400),
                                    corner: .bottomRight, area: area, using: window)
        #expect(window.presentedFrames.count == 2)
        #expect(window.presentedFrames.allSatisfy { area.contains($0) })
        #expect(window.frame == CGRect(x: 200, y: 100, width: 400, height: 700))
    }

    @Test func animatedReadbackDoesNotPullTheOppositeEdgeAround() throws {
        final class AnimatingWindow: WindowFrameAccess {
            var reads = 0
            var sizes: [CGSize] = []
            var positions: [CGPoint] = []
            func readFrame() -> CGRect? {
                defer { reads += 1 }
                switch reads {
                case 0: return CGRect(x: 200, y: 150, width: 400, height: 300)
                case 1: return CGRect(x: 200, y: 150, width: 440, height: 340)
                default: return CGRect(x: 200, y: 150, width: 480, height: 380)
                }
            }
            func setPosition(_ point: CGPoint) -> Bool { positions.append(point); return true }
            func setSize(_ size: CGSize) -> Bool { sizes.append(size); return true }
        }
        let window = AnimatingWindow()
        try FrameTransaction.resize(start: start, delta: CGPoint(x: 100, y: 100),
                                    corner: .bottomRight, area: area, using: window)
        #expect(window.sizes == [CGSize(width: 500, height: 400)])
        #expect(window.positions.isEmpty)
    }

    @Test func minimumWidthPushNeverSnapsBackToTheUnconstrainedOrigin() throws {
        // Recorded Safari failure: a 574 pt minimum with 2 position writes per
        // sample, jumping between the unconstrained and corrected push positions.
        let display = CGRect(x: 89, y: 30, width: 6055, height: 1698)
        let initial = CGRect(x: 3198, y: 30, width: 1202, height: 1698)
        let window = DisplayClampedWindow(frame: initial, area: display)
        window.minimum.width = 574
        for dx in [-700.0, -1000, -1548, -1550, -1480, -900, -650, -600, 0] {
            let previous = window.frame
            window.presentedFrames = []
            let expected = WindowGeometry.resize(start: initial, delta: CGPoint(x: dx, y: -784),
                                                  corner: .bottomRight, area: display, minimum: window.minimum)!
            let result = try FrameTransaction.resize(start: initial, delta: CGPoint(x: dx, y: -784),
                                                     corner: .bottomRight, area: display, using: window)
            #expect(result == expected)
            #expect(window.presentedFrames.allSatisfy {
                $0.minX >= min(previous.minX, expected.minX) && $0.minX <= max(previous.minX, expected.minX)
            })
            #expect(window.presentedFrames.filter { $0.origin != previous.origin }.count <= 1)
        }
    }

    @Test(arguments: Corner.allCases)
    func minimumContactAndReversalDoNotBounceOnEitherAxis(corner: Corner) throws {
        let window = DisplayClampedWindow(frame: start, area: area)
        window.minimum = CGSize(width: 300, height: 200)
        for amount in [120.0, 150, 170, 200, 170, 150, 120, 80, 0] {
            let previous = window.frame
            window.presentedFrames = []
            let delta = CGPoint(x: corner.left ? amount : -amount, y: corner.top ? amount : -amount)
            let expected = WindowGeometry.resize(start: start, delta: delta, corner: corner,
                                                  area: area, minimum: window.minimum)!
            #expect(try FrameTransaction.resize(start: start, delta: delta, corner: corner,
                                                area: area, using: window) == expected)
            #expect(window.presentedFrames.allSatisfy {
                $0.minX >= min(previous.minX, expected.minX) && $0.minX <= max(previous.minX, expected.minX)
                    && $0.minY >= min(previous.minY, expected.minY) && $0.minY <= max(previous.minY, expected.minY)
            })
        }
    }

    @Test func nativeSizeIncrementsAreNotCachedAsPermanentMinimums() throws {
        final class GridWindow: WindowFrameAccess {
            var frame = CGRect(x: 200, y: 150, width: 400, height: 300)
            func readFrame() -> CGRect? { frame }
            func setPosition(_ point: CGPoint) -> Bool { frame.origin = point; return true }
            func setSize(_ size: CGSize) -> Bool {
                frame.size = CGSize(width: max(100, (size.width / 10).rounded(.up) * 10), height: size.height)
                return true
            }
        }
        let window = GridWindow()
        for dx in [-25.0, -35, -75, -105, -305, -205, 0] {
            let result = try FrameTransaction.resize(start: start, delta: CGPoint(x: dx, y: 0),
                                                     corner: .bottomRight, area: area, using: window)
            let expectedWidth: CGFloat = max(100, ((start.width + CGFloat(dx)) / 10).rounded(.up) * 10)
            let expectedRight: CGFloat = start.maxX + CGFloat(dx)
            #expect(result.width == expectedWidth)
            #expect(result.maxX == expectedRight)
        }
    }

    @Test func bottomCollisionMovesTopUpBeforeGrowing() throws {
        let window = DisplayClampedWindow(frame: start, area: area)
        // A size-only request cannot fit the desired 700 pt height at y=150.
        #expect(window.setSize(CGSize(width: 400, height: 700)))
        #expect(window.frame.height == 650)
        window.frame = start

        let result = try FrameTransaction.resize(start: start, delta: CGPoint(x: 0, y: 400),
                                                 corner: .bottomRight, area: area, using: window)
        #expect(result == CGRect(x: 200, y: 100, width: 400, height: 700))
        #expect(result.maxY == area.maxY)
    }

    @Test(arguments: Corner.allCases)
    func allWallsPushOppositeEdgesAndReverse(corner: Corner) throws {
        let window = DisplayClampedWindow(frame: start, area: area)
        let delta = CGPoint(x: corner.left ? -300 : 500, y: corner.top ? -200 : 400)
        let expected = CGRect(x: corner.left ? 0 : 100, y: corner.top ? 30 : 100,
                              width: corner.left ? 700 : 900, height: corner.top ? 500 : 700)
        for _ in 0..<3 {
            #expect(try FrameTransaction.resize(start: start, delta: delta, corner: corner,
                                                area: area, using: window) == expected)
        }
        let far = CGPoint(x: corner.left ? -2000 : 2000, y: corner.top ? -2000 : 2000)
        #expect(try FrameTransaction.resize(start: start, delta: far, corner: corner,
                                            area: area, using: window) == area)
        #expect(try FrameTransaction.resize(start: start, delta: delta, corner: corner,
                                            area: area, using: window) == expected)
        #expect(try FrameTransaction.resize(start: start, delta: .zero, corner: corner,
                                            area: area, using: window) == start)
    }

    @Test func mixedShrinkAndGrowthMakesRoomOnBothAxes() throws {
        let window = DisplayClampedWindow(frame: area, area: area)
        let tall = CGRect(x: 800, y: 30, width: 200, height: 770)
        let wide = CGRect(x: 0, y: 650, width: 1000, height: 150)
        #expect(try FrameTransaction.setFrame(tall, using: window) == tall)
        #expect(try FrameTransaction.setFrame(wide, using: window) == wide)
        #expect(try FrameTransaction.setFrame(tall, using: window) == tall)
    }

    @Test func intrinsicMinimumAndMaximumStillPushAndPull() throws {
        let window = DisplayClampedWindow(frame: start, area: area)
        window.minimum = CGSize(width: 300, height: 200)
        window.maximum = CGSize(width: 450, height: 350)
        #expect(try FrameTransaction.resize(start: start, delta: CGPoint(x: -150, y: -150),
                                            corner: .bottomRight, area: area, using: window)
                == CGRect(x: 150, y: 100, width: 300, height: 200))
        #expect(try FrameTransaction.resize(start: start, delta: CGPoint(x: 100, y: 100),
                                            corner: .bottomRight, area: area, using: window)
                == CGRect(x: 250, y: 200, width: 450, height: 350))
        #expect(try FrameTransaction.resize(start: start, delta: CGPoint(x: 500, y: 400),
                                            corner: .bottomRight, area: area, using: window)
                == CGRect(x: 550, y: 450, width: 450, height: 350))
    }

    @Test func correctsAppsThatReanchorSizeAtTheBottom() throws {
        let window = DisplayClampedWindow(frame: start, area: area)
        window.anchorsSizeAtBottom = true
        let desired = CGRect(x: 100, y: 100, width: 900, height: 700)
        #expect(try FrameTransaction.setFrame(desired, using: window) == desired)
        #expect(try FrameTransaction.setFrame(start, using: window) == start)
    }

    @Test func movesBetweenDisplaysBeforeGrowing() throws {
        let otherArea = CGRect(x: -1200, y: -800, width: 1200, height: 800)
        let window = DisplayClampedWindow(frame: start, area: otherArea)
        #expect(try FrameTransaction.setFrame(otherArea, area: otherArea, using: window) == otherArea)
    }

    @Test func propagatesFailedSizeWrites() throws {
        let window = DisplayClampedWindow(frame: start, area: area)
        window.refusesSize = true
        #expect(throws: FrameTransactionError.sizeRefused) {
            try FrameTransaction.resize(start: start, delta: CGPoint(x: 0, y: 400),
                                        corner: .bottomRight, area: area, using: window)
        }
    }
}
