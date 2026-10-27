import Testing
@testable import WindowBehavior

struct BackgroundHitPolicyTests {
    @Test func finderEmptyCollectionsAllowMovingButTheirContentsStayProtected() {
        for role in ["AXOutline", "AXList", "AXTable"] {
            var empty = BackgroundHitPolicy(bundleID: "com.apple.finder")
            #expect({ empty.permits(role: role) }())
            #expect({ empty.permits(role: "AXScrollArea") }())
            #expect({ empty.permits(role: "AXWindow") }())
            #expect(empty.requiresUniformPixels)
            var child = BackgroundHitPolicy(bundleID: "com.apple.finder")
            #expect({ child.permits(role: "AXGroup") }())
            #expect({ !child.permits(role: role) }())
            #expect(!permits([role, "AXWindow"]))
        }
        for role in ["AXRow", "AXCell", "AXImage", "AXStaticText", "AXTextField"] {
            var policy = BackgroundHitPolicy(bundleID: "com.apple.finder")
            #expect({ !policy.permits(role: role) }())
        }
    }

    @Test func messagesWallpaperOnlyBypassesPixelsForDirectTranscriptHits() {
        var empty = BackgroundHitPolicy(bundleID: "com.apple.iChat")
        #expect({ empty.permits(role: "AXGroup", identifier: "TranscriptCollectionView") }())
        #expect({ empty.permits(role: "AXGroup") }())
        #expect({ empty.permits(role: "AXWindow") }())
        #expect(!empty.requiresUniformPixels)
        for bundle in ["com.apple.iChat", "other.app"] {
            var child = BackgroundHitPolicy(bundleID: bundle)
            #expect({ child.permits(role: "AXGroup") }())
            #expect({ child.permits(role: "AXGroup", identifier: "TranscriptCollectionView") }())
            #expect(child.requiresUniformPixels)
            var bubble = BackgroundHitPolicy(bundleID: bundle)
            #expect({ !bubble.permits(role: "AXTextArea", identifier: "TranscriptCollectionView") }())
        }
        var other = BackgroundHitPolicy(bundleID: "other.app")
        #expect({ other.permits(role: "AXGroup", identifier: "TranscriptCollectionView") }())
        #expect(other.requiresUniformPixels)
        var sidebar = BackgroundHitPolicy(bundleID: "com.apple.iChat")
        #expect({ sidebar.permits(role: "AXGroup", identifier: "ConversationList") }())
        #expect(sidebar.requiresUniformPixels)
    }

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
