import Testing
@testable import WindowBehavior

struct ResizeAnimationScopeTests {
    @Test func holdsDirectResizingForTheGestureAndRestoresTheOriginalSetting() {
        var enhanced = true
        var changes: [Bool] = []
        let scope = ResizeAnimationScope(assistiveTechnologyActive: false, read: { enhanced }, write: {
            enhanced = $0; changes.append($0); return true
        })
        for _ in 0..<50 { scope.begin(); #expect(!enhanced) }
        #expect(changes == [false])
        #expect(scope.end())
        #expect(enhanced)
        #expect(scope.end())
        #expect(changes == [false, true])
    }

    @Test(arguments: [false, true])
    func preservesAssistiveTechnologyAndAlreadyDisabledSettings(assistiveTechnology: Bool) {
        var changes: [Bool] = []
        let scope = ResizeAnimationScope(assistiveTechnologyActive: assistiveTechnology,
                                         read: { assistiveTechnology }, write: { changes.append($0); return true })
        scope.begin()
        scope.end()
        #expect(changes.isEmpty)
    }

    @Test func unsupportedSettingNeedsNoRestoration() {
        var changes: [Bool] = []
        let scope = ResizeAnimationScope(assistiveTechnologyActive: false,
                                         read: { true }, write: { changes.append($0); return false })
        scope.begin()
        #expect(scope.end())
        #expect(changes == [false])
    }

    @Test func restorationCanBeRetriedAfterAnAppTimeout() {
        var enhanced = true
        var refuseRestore = true
        let scope = ResizeAnimationScope(assistiveTechnologyActive: false, read: { enhanced }, write: {
            if $0 && refuseRestore { return false }
            enhanced = $0
            return true
        })
        scope.begin()
        #expect(!scope.end())
        refuseRestore = false
        #expect(scope.end())
        #expect(enhanced)
    }
}
