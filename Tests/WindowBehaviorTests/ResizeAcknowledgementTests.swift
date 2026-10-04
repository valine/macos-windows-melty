import CoreGraphics
import Testing
@testable import WindowBehavior

struct ResizeAcknowledgementTests {
    @Test func timeoutWithAppliedResizeOrNativeClampCanContinue() {
        let before = CGSize(width: 900, height: 700)
        let requested = CGSize(width: 700, height: 600)
        #expect(ResizeAcknowledgement.applied(previous: before, requested: requested, observed: requested))
        #expect(ResizeAcknowledgement.applied(previous: before, requested: requested,
                                            observed: CGSize(width: 800, height: 600)))
    }
    @Test func failedOrUnrelatedReadbacksDoNotMaskARefusal() {
        let before = CGSize(width: 900, height: 700)
        let requested = CGSize(width: 700, height: 600)
        #expect(!ResizeAcknowledgement.applied(previous: before, requested: requested, observed: before))
        #expect(!ResizeAcknowledgement.applied(previous: before, requested: requested, observed: nil))
        #expect(!ResizeAcknowledgement.applied(previous: before, requested: requested,
                                             observed: CGSize(width: 950, height: 600)))
    }
}
