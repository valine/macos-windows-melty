import AppKit
import ApplicationServices
import WindowBehavior

enum AX {
    static func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }
    static func element(_ source: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = value(source, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    static func string(_ element: AXUIElement, _ name: String) -> String? { value(element, name) as? String }
    static func bool(_ element: AXUIElement, _ name: String) -> Bool { (value(element, name) as? Bool) == true }
    static func settable(_ element: AXUIElement, _ name: String) -> Bool {
        var result = DarwinBoolean(false)
        return AXUIElementIsAttributeSettable(element, name as CFString, &result) == .success && result.boolValue
    }
    static func frame(_ element: AXUIElement) -> CGRect? {
        // One IPC round trip for position and size also avoids mixing two
        // different frames while the target app is still updating its geometry.
        var attributes: CFArray?
        let error = AXUIElementCopyMultipleAttributeValues(element,
            [kAXPositionAttribute, kAXSizeAttribute] as CFArray, [], &attributes)
        let values: [CFTypeRef]?
        if error == .success { values = attributes as? [CFTypeRef] }
        else if let position = value(element, kAXPositionAttribute), let size = value(element, kAXSizeAttribute) {
            values = [position, size]
        } else { values = nil }
        guard let values, values.count == 2 else { return nil }
        let p = values[0], s = values[1]
        guard
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size),
              size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: point, size: size)
    }
    static func position(_ element: AXUIElement, _ point: CGPoint) -> AXError {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return .failure }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
    }
    static func size(_ element: AXUIElement, _ size: CGSize) -> AXError {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return .failure }
        return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
    }
}

final class WindowTarget {
    let element: AXUIElement
    let pid: pid_t
    let name: String
    let bundleID: String
    let initial: CGRect
    let windowID: CGWindowID
    let sampleIsUnobscured: Bool
    var accessQueue: DispatchQueue { WindowAccessQueue.forProcess(pid) }

    init(element: AXUIElement, pid: pid_t, name: String, bundleID: String, initial: CGRect,
         windowID: CGWindowID, sampleIsUnobscured: Bool) {
        self.element = element; self.pid = pid; self.name = name; self.bundleID = bundleID
        self.initial = initial; self.windowID = windowID; self.sampleIsUnobscured = sampleIsUnobscured
    }
}

enum WindowAccess {
    // External IPC stays off the input loop; self-targeted AX calls execute
    // AppKit synchronously and must use the main queue instead.
    static let queue = WindowAccessQueue.external

    static func resolutionQueue(at point: CGPoint) -> DispatchQueue {
        dispatchPrecondition(condition: .onQueue(.main))
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        // Conservatively use main anywhere inside our visible windows. Normal
        // AX and WindowServer hit tests still reject obscured/ineligible targets.
        let ownWindow = NSApp.windows.contains { window in
            let frame = window.frame
            return window.isVisible && !window.isMiniaturized
                && CGRect(x: frame.minX, y: top - frame.maxY,
                          width: frame.width, height: frame.height).contains(point)
        }
        return ownWindow ? .main : queue
    }

    static func resolve(point: CGPoint, resize: Bool, exclusions: Set<String>, radius: Int) -> WindowTarget? {
        let began = Date()
        defer { Trace.write("resolve duration=\(Int(Date().timeIntervalSince(began) * 1000))ms") }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.04)
        var hit: AXUIElement?
        let hitError = AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit)
        guard hitError == .success, let hit else { Trace.write("reject AX hit error=\(hitError.rawValue)"); return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(hit, &pid) == .success,
              let app = NSRunningApplication(processIdentifier: pid) else { Trace.write("reject hit pid=\(pid), self=\(getpid())"); return nil }
        // A window can move between scheduling and hit-testing. Re-enter on
        // main before reading its AppKit accessibility attributes in that case.
        if pid == getpid(), !Thread.isMainThread {
            return DispatchQueue.main.sync {
                resolve(point: point, resize: resize, exclusions: exclusions, radius: radius)
            }
        }
        let bundle = app.bundleIdentifier ?? ""
        let name = app.localizedName ?? bundle
        guard !exclusions.contains(bundle.lowercased()), !exclusions.contains(name.lowercased()),
              bundle != "com.apple.finder" || AX.string(hit, kAXRoleAttribute) != "AXScrollArea" else { Trace.write("reject exclusion app=\(bundle)"); return nil }

        let window = owningWindow(hit, pid: pid, point: point,
                                  allowSettingsFallback: resize && bundle == "com.apple.systempreferences")
        guard let window else { Trace.write("reject no AX window app=\(bundle) hitRole=\(AX.string(hit, kAXRoleAttribute) ?? "nil")"); return nil }
        Trace.write("target app=\(bundle) hitRole=\(AX.string(hit, kAXRoleAttribute) ?? "nil") subrole=\(AX.string(window, kAXSubroleAttribute) ?? "nil") movable=\(AX.settable(window, kAXPositionAttribute)) resizable=\(AX.settable(window, kAXSizeAttribute))")
        guard AX.string(window, kAXSubroleAttribute) == kAXStandardWindowSubrole,
              !AX.bool(window, "AXFullScreen"), !AX.bool(window, kAXMinimizedAttribute),
              !AX.bool(window, kAXModalAttribute),
              !((AX.value(window, kAXChildrenAttribute) as? [AXUIElement]) ?? []).contains(where: { AX.string($0, kAXRoleAttribute) == kAXSheetRole }),
              AX.settable(window, kAXPositionAttribute),
              !resize || AX.settable(window, kAXSizeAttribute),
              let frame = AX.frame(window), frame.contains(point) else { Trace.write("reject window eligibility"); return nil }
        AXUIElementSetMessagingTimeout(window, 0.04)

        if !resize {
            guard backgroundElement(hit, window: window) else { Trace.write("reject background AX role"); return nil }
            let browsers = ["com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox", "com.brave.Browser", "com.microsoft.edgemac"]
            if browsers.contains(bundle) && point.y - frame.minY < 80 { Trace.write("reject browser toolbar"); return nil }
        }

        // Match public AX geometry to the actual topmost WindowServer window.
        // Never silently substitute the focused window or click through a popup.
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let records: [WindowRecord] = windows.compactMap { info in
            guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  let id = info[kCGWindowNumber as String] as? UInt32,
                  let owner = info[kCGWindowOwnerPID as String] as? Int32,
                  let layer = info[kCGWindowLayer as String] as? Int else { return nil }
            return WindowRecord(id: id, pid: owner, layer: layer, alpha: info[kCGWindowAlpha as String] as? Double ?? 1, frame: rect)
        }
        let sample = WindowGeometry.sampleRect(at: point, frame: frame, radius: radius)
        guard let match = WindowStack.match(records, pid: pid, frame: frame, point: point, sample: sample) else {
            Trace.write("reject no matching normal CG window AX=\(frame)")
            return nil
        }
        Trace.write("accept target window=\(match.id) unobscured=\(match.unobscured)")
        return WindowTarget(element: window, pid: pid, name: name, bundleID: bundle, initial: frame,
                            windowID: match.id, sampleIsUnobscured: match.unobscured)
    }

    private static func owningWindow(_ hit: AXUIElement, pid: pid_t, point: CGPoint,
                                     allowSettingsFallback: Bool) -> AXUIElement? {
        var current: AXUIElement? = hit
        var visited: [AXUIElement] = []
        for depth in 0..<32 {
            guard let item = current, !visited.contains(where: { CFEqual($0, item) }) else { break }
            visited.append(item)
            if AX.string(item, kAXRoleAttribute) == kAXWindowRole { return item }
            if let window = AX.element(item, kAXWindowAttribute) {
                if depth > 0 { Trace.write("window resolved through ancestor depth=\(depth)") }
                return window
            }
            current = AX.element(item, kAXParentAttribute)
        }
        // Settings' hosted detail panes can omit AXWindow and have a detached
        // parent chain. For right-drag only, use a unique window of the hit app
        // containing the press. Never substitute its focused/main window.
        // The caller still checks eligibility and the topmost WindowServer
        // frame before accepting it. Left-drag retains its control ancestry gate.
        guard allowSettingsFallback else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.04)
        let windows = (AX.value(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        let candidates = windows.filter {
            !AX.bool($0, kAXMinimizedAttribute) && (AX.frame($0)?.contains(point) == true)
        }
        guard candidates.count == 1 else {
            Trace.write("reject Settings window fallback candidates=\(candidates.count)")
            return nil
        }
        Trace.write("window resolved through Settings geometry fallback")
        return candidates[0]
    }

    private static func backgroundElement(_ hit: AXUIElement, window: AXUIElement) -> Bool {
        var policy = BackgroundHitPolicy()
        var roles: [String] = []
        var current: AXUIElement? = hit
        // Web pages can have more than 16 layout containers. The gesture's
        // existing total deadline still bounds takeover if AX is slow.
        for _ in 0..<64 {
            guard let item = current else {
                Trace.write("background missing parent roles=\(roles.joined(separator: ">"))")
                return false
            }
            let role = AX.string(item, kAXRoleAttribute) ?? "missing"
            roles.append(role)
            guard policy.permits(role: role) else {
                Trace.write("background protected roles=\(roles.joined(separator: ">"))")
                return false
            }
            if CFEqual(item, window) { return true }
            current = AX.element(item, kAXParentAttribute)
        }
        Trace.write("background ancestor limit roles=\(roles.joined(separator: ">"))")
        return false
    }

    static func isStillAtStart(_ target: WindowTarget) -> Bool {
        guard let frame = AX.frame(target.element) else { return false }
        return frame == target.initial
    }
}

struct FrameRequest: Equatable {
    let start: CGRect
    let delta: CGPoint
    let corner: Corner?
    let area: CGRect
    var restoring = false
}

private final class AXFrameAccess: WindowFrameAccess {
    let element: AXUIElement
    var reads = 0
    var moves = 0
    var sizes = 0
    private var lastFrame: CGRect?
    init(element: AXUIElement) { self.element = element }
    func readFrame() -> CGRect? {
        reads += 1
        lastFrame = AX.frame(element)
        return lastFrame
    }
    func setPosition(_ point: CGPoint) -> Bool { moves += 1; return AX.position(element, point) == .success }
    func setSize(_ size: CGSize) -> Bool {
        sizes += 1
        let previous = lastFrame?.size
        let error = AX.size(element, size)
        guard error != .success else { return true }
        let observed = readFrame()?.size
        let applied = error == .cannotComplete && ResizeAcknowledgement.applied(
            previous: previous, requested: size, observed: observed)
        Trace.write("size acknowledgement error=\(error.rawValue) previous=\(String(describing: previous)) requested=\(size) observed=\(String(describing: observed)) applied=\(applied)")
        return applied
    }
}

/// At most one AX transaction is in flight. New mouse samples replace queued
/// work instead of building a backlog at 1000 Hz. Position and size are separate
/// macOS attributes, so every write is read back and app constraints are honored.
final class FrameWriter {
    let target: WindowTarget
    private let animationScope: ResizeAnimationScope
    private var terminationObserver: NSObjectProtocol?
    private let requests = LatestFrameRequest<FrameRequest>()
    private var pending: FrameRequest? {
        get { requests.pending }
        set { requests.pending = newValue }
    }
    private var busy = false
    private var stopped = false
    private var lastRequest: FrameRequest?
    // Main-thread state, remembered only for this utility session.
    private static var pacingByPID: [pid_t: ResizePacing] = [:]
    private var pacing: ResizePacing
    private var completedAt = 0.0
    private var scheduled: DispatchWorkItem?
    var onFailure: ((String) -> Void)?
    var afterDrain: (() -> Void)?

    init(target: WindowTarget) {
        self.target = target
        pacing = Self.pacingByPID[target.pid] ?? ResizePacing()
        let app = AXUIElementCreateApplication(target.pid)
        AXUIElementSetMessagingTimeout(app, 0.04)
        let scope = ResizeAnimationScope(
            assistiveTechnologyActive: NSWorkspace.shared.isVoiceOverEnabled || NSWorkspace.shared.isSwitchControlEnabled,
            // Our own AppKit window does not need an external AX animation
            // override. In particular, never wait for self-IPC during quit.
            read: { target.pid == getpid() ? nil : AX.value(app, "AXEnhancedUserInterface") as? Bool },
            write: { enabled in
                let result = AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString,
                                                         enabled ? kCFBooleanTrue : kCFBooleanFalse)
                Trace.write("resize animation enhancedUI=\(enabled) result=\(result.rawValue)")
                return result == .success
            })
        animationScope = scope
        if target.pid != getpid() {
            terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                                                         object: nil, queue: .main) { _ in
                // Quit can arrive mid-gesture, before the main-loop drain callback.
                WindowAccess.queue.sync { scope.end() }
            }
        }
    }

    deinit {
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
        let scope = animationScope
        target.accessQueue.async { scope.end() }
    }

    func submit(_ request: FrameRequest) {
        guard !stopped, request != lastRequest else { return }
        lastRequest = request
        pending = request
        flush()
    }
    func discardPending() {
        scheduled?.cancel(); scheduled = nil
        pending = nil; stopped = true
        let scope = animationScope
        target.accessQueue.async { scope.end() }
    }
    func finish(_ completion: @escaping () -> Void) {
        afterDrain = completion
        // Deliver the final pointer sample without an extra pacing delay.
        scheduled?.cancel(); scheduled = nil
        flush()
        completeIfDrained()
    }
    private func completeIfDrained() {
        guard !busy, pending == nil, let done = afterDrain else { return }
        afterDrain = nil
        let scope = animationScope
        target.accessQueue.async {
            scope.end()
            DispatchQueue.main.async(execute: done)
        }
    }
    private func flush() {
        guard !busy, !stopped, scheduled == nil, let request = pending else { return }
        if request.corner != nil && !request.restoring && afterDrain == nil {
            let delay = completedAt + pacing.recovery - ProcessInfo.processInfo.systemUptime
            if delay > 0 {
                let work = DispatchWorkItem { [weak self] in
                    self?.scheduled = nil
                    self?.flush()
                }
                scheduled = work
                DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
                return
            }
        }
        busy = true
        let target = target
        target.accessQueue.async { [self] in
            if request.corner != nil { self.animationScope.begin() }
            // Queue waiting and the initial animation-scope AX call can take
            // multiple mouse samples. Select after both, not at dispatch time.
            guard let request = self.requests.take() else {
                self.animationScope.end()
                DispatchQueue.main.async {
                    self.busy = false
                    self.completeIfDrained()
                }
                return
            }
            let began = ProcessInfo.processInfo.systemUptime
            let failure = Self.apply(request, to: target)
            let duration = ProcessInfo.processInfo.systemUptime - began
            if let failure { Trace.write("frame failure app=\(target.bundleID) reason=\(failure)") }
            if failure != nil { self.animationScope.end() }
            DispatchQueue.main.async {
                self.busy = false
                self.completedAt = ProcessInfo.processInfo.systemUptime
                if request.corner != nil && !request.restoring && failure == nil {
                    let wasSlow = self.pacing.slow
                    self.pacing.record(seconds: duration)
                    if Self.pacingByPID.count > 128 { Self.pacingByPID.removeAll() }
                    Self.pacingByPID[target.pid] = self.pacing
                    if wasSlow != self.pacing.slow {
                        Trace.write("adaptive resize app=\(target.bundleID) slow=\(self.pacing.slow) responseMs=\(Int(duration * 1000))")
                    }
                }
                if let failure { self.pending = nil; self.stopped = true; self.onFailure?(failure) }
                if self.pending != nil { self.flush() }
                else { self.completeIfDrained() }
            }
        }
    }

    private static func apply(_ request: FrameRequest, to target: WindowTarget) -> String? {
        let began = ProcessInfo.processInfo.systemUptime
        let element = target.element
        // A slow first response must survive long enough to be measured. This
        // is a maximum reply budget, not a delay, and is off the input thread.
        let resizing = request.corner != nil
        if resizing { AXUIElementSetMessagingTimeout(element, 0.5) }
        defer { if resizing { AXUIElementSetMessagingTimeout(element, 0.04) } }
        Trace.write("write corner=\(String(describing: request.corner)) delta=\(request.delta) restore=\(request.restoring)")
        let access = AXFrameAccess(element: element)
        do {
            if request.restoring {
                try FrameTransaction.setFrame(request.start, area: request.area, using: access)
            } else if let corner = request.corner {
                let accepted = try FrameTransaction.resize(start: request.start, delta: request.delta,
                                                            corner: corner, area: request.area, using: access)
                Trace.write("resize start=\(request.start) area=\(request.area) accepted=\(accepted) reads=\(access.reads) moves=\(access.moves) sizes=\(access.sizes) ms=\(Int((ProcessInfo.processInfo.systemUptime - began) * 1000))")
            } else {
                let frame = WindowGeometry.move(start: request.start, delta: request.delta, area: request.area)
                guard access.setPosition(frame.origin) else { return "This app refused the window move." }
            }
            return nil
        } catch FrameTransactionError.unavailable {
            return "The window closed during the resize."
        } catch FrameTransactionError.positionRefused {
            return "This app refused the resize position."
        } catch FrameTransactionError.sizeRefused {
            return "This app refused the window resize."
        } catch {
            return "This app's window constraints do not fit the available display area."
        }
    }
}
