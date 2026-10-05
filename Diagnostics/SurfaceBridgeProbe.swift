// Build with SurfaceBridge.swift, Trace.swift, and the WindowBehavior module.
// An isolated endpoint tests the actual transport without touching the installed app.
import AppKit

@main
enum SurfaceBridgeProbe {
    static func main() {
        _ = NSApplication.shared
        let bridge = SurfaceBridge(path: CommandLine.arguments[1])
        bridge.setEnabled(true)
        print("ready")
        fflush(stdout)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { bridge.setEnabled(false) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { exit(0) }
        withExtendedLifetime(bridge) { RunLoop.main.run() }
    }
}
