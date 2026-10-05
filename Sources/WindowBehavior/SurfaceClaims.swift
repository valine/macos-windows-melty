import Foundation

/// A short-lived agreement that a surface handles its own layout gestures.
/// The caller supplies the authenticated peer PID, never a PID from JSON.
public struct SurfaceClaims {
    private var claims: [UInt32: (pid: Int32, expiry: TimeInterval)] = [:]
    public init() {}
    public mutating func replace(pid: Int32, windows: [UInt32], now: TimeInterval) {
        claims = claims.filter { $0.value.expiry > now && $0.value.pid != pid }
        for window in windows { claims[window] = (pid, now + 2) }
    }
    public func owns(window: UInt32, now: TimeInterval) -> Bool {
        guard let claim = claims[window] else { return false }
        return claim.expiry > now
    }
    public func owns(pid: Int32, window: UInt32, now: TimeInterval) -> Bool {
        guard let claim = claims[window] else { return false }
        return claim.pid == pid && claim.expiry > now
    }
}
