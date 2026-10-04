import Testing
@testable import WindowBehavior

struct BackgroundHitPolicyTests {
    private func permits(_ roles: [String]) -> Bool {
        var policy = BackgroundHitPolicy()
        return roles.allSatisfy { policy.permits(role: $0) }
    }

    @Test func safariPageInsideBrowserTabContainer() {
        // Observed Safari hierarchy: page -> scroll area -> tab group -> split -> window.
        let ancestors = ["AXWebArea", "AXScrollArea", "AXTabGroup", "AXSplitGroup", "AXWindow"]
        #expect(permits(ancestors))
        #expect(permits(["AXGroup", "AXGroup"] + ancestors))
    }

    @Test func pageControlsStillOwnTheirDrags() {
        for control in ["AXLink", "AXButton", "AXTextField", "AXTextArea", "AXScrollBar", "AXList", "AXTable", "AXTabGroup"] {
            let ancestors = [control, "AXWebArea", "AXScrollArea", "AXTabGroup", "AXWindow"]
            #expect(!permits(ancestors))
            #expect(!permits(["AXGroup"] + ancestors))
        }
        #expect(!permits(["AXStaticText", "AXWebArea", "AXTabGroup", "AXWindow"]))
        #expect(!permits(["AXImage", "AXWebArea", "AXTabGroup", "AXWindow"]))
    }

    @Test func exemptionOnlyAppliesToOuterTabContainer() {
        #expect(!permits(["AXGroup", "AXTabGroup", "AXWindow"]))
        #expect(!permits(["AXWebArea", "AXButton", "AXTabGroup", "AXWindow"]))
        #expect(permits(["AXGroup", "AXScrollArea", "AXWindow"]))
    }
}
