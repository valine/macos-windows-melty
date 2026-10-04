import Testing
@testable import WindowBehavior

struct ResizePacingTests {
    @Test func fastAppsRemainUnthrottled() {
        var pacing = ResizePacing()
        for _ in 0..<100 { pacing.record(seconds: 0.008) }
        #expect(!pacing.slow)
        #expect(pacing.recovery == 0)
        pacing.record(seconds: 0.06)
        #expect(!pacing.slow)
    }
    @Test func musicLatencyEnablesBoundedRecovery() {
        var pacing = ResizePacing()
        pacing.record(seconds: 0.075)
        pacing.record(seconds: 0.123)
        #expect(pacing.slow)
        #expect(pacing.recovery >= 0.016)
        #expect(pacing.recovery <= 0.1)
        for _ in 0..<100 { pacing.record(seconds: 2) }
        #expect(pacing.recovery == 0.1)
    }
    @Test func recoversWithoutFlappingOnOneFastResponse() {
        var pacing = ResizePacing()
        pacing.record(seconds: 0.12)
        for _ in 0..<7 { pacing.record(seconds: 0.01) }
        #expect(pacing.slow)
        pacing.record(seconds: 0.01)
        #expect(!pacing.slow)
        #expect(pacing.recovery == 0)
    }
}
