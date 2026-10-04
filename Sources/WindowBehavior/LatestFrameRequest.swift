import Foundation

/// A worker takes the newest value only when ready to execute it. Values
/// submitted while that execution is in progress become the next request.
public final class LatestFrameRequest<Value> {
    private let lock = NSLock()
    private var value: Value?
    public init() {}
    public var pending: Value? {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); defer { lock.unlock() }; value = newValue }
    }
    public func take() -> Value? {
        lock.lock(); defer { lock.unlock() }
        let latest = value
        value = nil
        return latest
    }
}
