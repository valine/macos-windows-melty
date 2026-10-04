import Testing
@testable import WindowBehavior

struct LatestFrameRequestTests {
    @Test func delayedWorkerUsesNewestSizeNotDispatchTimeSize() {
        let requests = LatestFrameRequest<Int>()
        requests.pending = 800
        // The queue is occupied or the app is answering the initial AX call.
        requests.pending = 850
        requests.pending = 920
        #expect(requests.take() == 920)
        #expect(requests.take() == nil)
    }
    @Test func inFlightWriteDoesNotEraseNextSample() {
        let requests = LatestFrameRequest<Int>()
        requests.pending = 800
        let writing = requests.take()
        requests.pending = 900
        #expect(writing == 800)
        #expect(requests.take() == 900)
    }
    @Test func cancellationAndRestoreReplaceQueuedResize() {
        let requests = LatestFrameRequest<Int>()
        requests.pending = 900
        requests.pending = nil
        #expect(requests.take() == nil)
        requests.pending = 1000
        requests.pending = 800 // Restore the press geometry.
        #expect(requests.take() == 800)
    }
}
