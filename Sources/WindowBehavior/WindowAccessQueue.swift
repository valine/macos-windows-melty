import Foundation

/// Self-targeted Accessibility calls may invoke AppKit directly on the caller's
/// thread. Only cross-process calls belong on the IPC worker.
public enum WindowAccessQueue {
    public static let external = DispatchQueue(label: "org.melty.windows.accessibility", qos: .userInteractive)

    public static func forProcess(_ pid: Int32) -> DispatchQueue {
        pid == ProcessInfo.processInfo.processIdentifier ? .main : external
    }
}
