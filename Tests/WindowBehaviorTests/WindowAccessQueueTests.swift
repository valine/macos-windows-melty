import Foundation
import Testing
@testable import WindowBehavior

struct WindowAccessQueueTests {
    @Test func ownWindowOperationsRunOnMainEvenWhenScheduledByWorker() async {
        let onMain = await withCheckedContinuation { continuation in
            WindowAccessQueue.external.async {
                WindowAccessQueue.forProcess(ProcessInfo.processInfo.processIdentifier).async {
                    continuation.resume(returning: Thread.isMainThread)
                }
            }
        }
        #expect(onMain)
    }

    @Test func otherAppsKeepIPCOffMain() async {
        let onMain = await withCheckedContinuation { continuation in
            WindowAccessQueue.forProcess(-1).async {
                continuation.resume(returning: Thread.isMainThread)
            }
        }
        #expect(!onMain)
    }
}
