/// AppKit can animate AX frame setters while Enhanced UI is enabled. Suspend
/// that behavior for a resize gesture, then restore exactly the original state.
/// Leave it alone when built-in assistive technology is using it.
public final class ResizeAnimationScope {
    private let allowed: Bool
    private let read: () -> Bool?
    private let write: (Bool) -> Bool
    private var began = false
    private var needsRestore = false

    public init(assistiveTechnologyActive: Bool, read: @escaping () -> Bool?, write: @escaping (Bool) -> Bool) {
        allowed = !assistiveTechnologyActive
        self.read = read
        self.write = write
    }

    public func begin() {
        guard !began else { return }
        began = true
        if allowed && read() == true { needsRestore = write(false) }
    }

    @discardableResult
    public func end() -> Bool {
        guard needsRestore else { return true }
        guard write(true) else { return false }
        needsRestore = false
        return true
    }
}
