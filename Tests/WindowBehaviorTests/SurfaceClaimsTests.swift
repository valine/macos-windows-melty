import Testing
@testable import WindowBehavior

struct SurfaceClaimsTests {
    @Test func surfacesAreScopedToTheirAuthenticatedProcessAndExpire() {
        var claims = SurfaceClaims()
        claims.replace(pid: 10, windows: [1, 2], now: 100)
        #expect(claims.owns(pid: 10, window: 1, now: 101))
        #expect(!claims.owns(pid: 11, window: 1, now: 101))
        #expect(!claims.owns(window: 3, now: 101))
        #expect(!claims.owns(window: 1, now: 102))
    }
    @Test func replacingSurfaceSetPreservesOtherApps() {
        var claims = SurfaceClaims()
        claims.replace(pid: 10, windows: [1, 2], now: 100)
        claims.replace(pid: 11, windows: [3], now: 100)
        claims.replace(pid: 10, windows: [2], now: 101)
        #expect(!claims.owns(window: 1, now: 101))
        #expect(claims.owns(window: 2, now: 102))
        #expect(claims.owns(window: 3, now: 101))
        claims.replace(pid: 10, windows: [], now: 101)
        #expect(!claims.owns(window: 2, now: 101))
    }
}
