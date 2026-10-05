import CoreGraphics
import Testing
@testable import WindowBehavior

struct ResizeGridTests {
    func learned() -> ResizeGrid {
        var grid = ResizeGrid()
        for i in 0..<3 {
            grid.record(requested: CGSize(width: 405 + i * 10, height: 310 + i * 20),
                        accepted: CGSize(width: 410 + i * 10, height: 320 + i * 20))
        }
        return grid
    }
    @Test func learnsIndependentRowAndColumnIncrements() {
        let grid = learned()
        #expect(grid.increments == CGSize(width: 10, height: 20))
        let start = CGRect(x: 200, y: 150, width: 400, height: 300)
        #expect(grid.delta(start: start, raw: CGPoint(x: 3, y: 7), corner: .bottomRight) == .zero)
        #expect(grid.delta(start: start, raw: CGPoint(x: 6, y: 11), corner: .bottomRight) == CGPoint(x: 10, y: 20))
    }
    @Test func aHardMinimumIsNotAResizeGrid() {
        var grid = ResizeGrid()
        for width in [290, 280, 270, 260] {
            grid.record(requested: CGSize(width: width, height: 200), accepted: CGSize(width: 300, height: 200))
        }
        #expect(grid.increments == .zero)
    }
    @Test func fastMotionDoesNotInventLargerCells() {
        var grid = ResizeGrid()
        for width in [495, 525, 555, 585] {
            grid.record(requested: CGSize(width: width, height: 200), accepted: CGSize(width: width + 5, height: 200))
        }
        #expect(grid.increments == .zero)
    }
    @Test func learnedGridDoesNotMoveTheWindowBetweenCellsAtWall() throws {
        final class Window: WindowFrameAccess {
            var frame = CGRect(x: 200, y: 150, width: 400, height: 300)
            var positions: [CGPoint] = []
            var sizes: [CGSize] = []
            func readFrame() -> CGRect? { frame }
            func setPosition(_ point: CGPoint) -> Bool { positions.append(point); frame.origin = point; return true }
            func setSize(_ size: CGSize) -> Bool {
                sizes.append(size)
                frame.size = CGSize(width: (size.width / 10).rounded() * 10, height: (size.height / 20).rounded() * 20)
                return true
            }
        }
        let window = Window(), start = window.frame
        let area = CGRect(x: 0, y: 30, width: 1000, height: 770), grid = learned()
        let first = try FrameTransaction.resize(start: start, delta: CGPoint(x: 0, y: 400), corner: .bottomRight, area: area, using: window, grid: grid)
        #expect(first.maxY == area.maxY)
        window.positions = []; window.sizes = []
        for dy in [401.0, 402, 407, 402, 400] {
            #expect(try FrameTransaction.resize(start: start, delta: CGPoint(x: 0, y: dy), corner: .bottomRight, area: area, using: window, grid: grid) == first)
        }
        #expect(window.positions.isEmpty)
        #expect(window.sizes.isEmpty)
    }
}
