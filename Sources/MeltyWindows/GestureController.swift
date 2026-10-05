import AppKit
import ApplicationServices
import WindowBehavior

private final class Gesture {
    let token = UUID()
    let button: CGMouseButton
    let press: CGEvent
    let displays: [DisplayArea]
    var display: DisplayArea
    var events: [CGEvent]
    var intent: DragIntent
    var pointer: VirtualPointer
    var target: WindowTarget?
    var writer: FrameWriter?
    var corner: Corner?
    var raised = false
    var changedGeometry = false
    var native: NativeResizeRoute?
    var nativeReady = false
    var nativeHandoff = false
    var collisionInNativeSession = false

    init(button: CGMouseButton, press: CGEvent, displays: [DisplayArea], display: DisplayArea) {
        self.button = button; self.press = press; self.displays = displays; self.display = display
        events = [press]
        intent = DragIntent(start: press.location, threshold: button == .left ? 12 : 8)
        pointer = VirtualPointer(press.location)
    }
    var request: FrameRequest {
        FrameRequest(start: target!.initial, delta: intent.delta, corner: corner, area: display.usable)
    }
}

final class GestureController {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var gesture: Gesture?
    private var swallowedButton: CGMouseButton?
    private var deferredReplay: [CGEvent]?
    private var drainingNativeRelease: CGEvent?
    private let settings = Settings.shared
    private static let replayTag: Int64 = 0x4D454C545957
    var status: (String) -> Void = { _ in }
    var running: Bool { tap != nil }

    func start() {
        guard tap == nil, AXIsProcessTrusted() else { return }
        let types: [CGEventType] = [.leftMouseDown, .leftMouseUp, .leftMouseDragged,
                                   .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                                   .otherMouseDown, .otherMouseUp, .otherMouseDragged, .mouseMoved,
                                   .scrollWheel, .keyDown, .keyUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let controller = Unmanaged<GestureController>.fromOpaque(context).takeUnretainedValue()
            return controller.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                         options: .defaultTap, eventsOfInterest: mask, callback: callback,
                                         userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            status("Mouse access unavailable. Check Accessibility, then reopen Melty Windows.")
            return
        }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Trace.write("tap started pid=\(getpid()) version=\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development")")
        status("Ready")
    }

    func stop() {
        if let release = drainingNativeRelease {
            replay([release])
            drainingNativeRelease = nil
        }
        if let gesture {
            releaseNative(gesture)
            finish(gesture, cancel: true, replayClick: !gesture.intent.committed)
        }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
    }

    func displayConfigurationChanged() {
        if let gesture { swallowedButton = gesture.button; finish(gesture, cancel: true, replayClick: false) }
    }

    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let gesture {
                swallowedButton = gesture.intent.committed ? gesture.button : nil
                finish(gesture, cancel: true, replayClick: !gesture.intent.committed)
            }
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            status("Mouse hook resumed")
            return false
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.replayTag { return false }
        if type == .leftMouseDown || type == .rightMouseDown {
            Trace.write("press type=\(type.rawValue) point=\(event.location) flags=\(event.flags.rawValue) enabled=\(settings.enabled) left=\(CGEventSource.buttonState(.combinedSessionState, button: .left)) right=\(CGEventSource.buttonState(.combinedSessionState, button: .right)) center=\(CGEventSource.buttonState(.combinedSessionState, button: .center))")
        }
        // A tentative move must settle before its click is replayed. Hold later
        // input too, so a rapid second click/chord cannot overtake the first.
        if deferredReplay != nil {
            if let copy = event.copy() { deferredReplay?.append(copy) }
            return true
        }
        if let button = swallowedButton {
            if type == upType(button) { swallowedButton = nil; return true }
            if type == dragType(button) { return true }
        }
        if type == .keyDown {
            guard event.getIntegerValueField(.keyboardEventKeycode) == 53, let gesture else { return false }
            swallowedButton = gesture.button
            finish(gesture, cancel: true, replayClick: false)
            status("Gesture cancelled")
            return true
        }
        if let active = gesture {
            if type == dragType(active.button) {
                if active.writer == nil {
                    if let copy = event.copy() { active.events.append(copy) }
                    if active.events.count >= 512 { failOpen(active); return true }
                }
                if let display = DisplayArea.at(event.location, in: active.displays) { active.display = display }
                if settings.continueAtEdge {
                    active.pointer.update(visible: event.location,
                                          relative: CGPoint(x: Double(event.getIntegerValueField(.mouseEventDeltaX)),
                                                            y: Double(event.getIntegerValueField(.mouseEventDeltaY))),
                                          display: active.display.frame)
                    active.intent.update(active.pointer.position)
                } else { active.intent.update(event.location) }
                update(active)
                if active.native != nil { return routeNativeDrag(active, event: event) }
                return true
            }
            if type == upType(active.button) {
                if active.collisionInNativeSession {
                    finish(active, cancel: false, replayClick: false)
                    return true
                }
                if let native = active.native, native.started {
                    rewriteNative(event, type: .leftMouseUp, point: native.lastPoint)
                    active.native = nil
                    gesture = nil
                    status("Ready")
                    Trace.write("native resize ended app=\(active.target?.bundleID ?? "")")
                    return false
                }
                if let copy = event.copy() { active.events.append(copy) }
                if active.writer == nil { failOpen(active) }
                else { finish(active, cancel: !active.intent.committed, replayClick: !active.intent.committed) }
                return true
            }
            if [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(type) {
                // A second button before commitment belongs to the application's chord.
                if !active.intent.committed || active.writer == nil {
                    if let copy = event.copy() { active.events.append(copy) }
                    finish(active, cancel: true, replayClick: true)
                    return true
                }
                swallowedButton = active.button
                finish(active, cancel: false, replayClick: false)
                return false
            }
            return false
        }

        guard settings.enabled, type == .leftMouseDown || type == .rightMouseDown else { return false }
        let button: CGMouseButton = type == .leftMouseDown ? .left : .right
        guard (button == .left ? settings.leftMove && CGPreflightScreenCaptureAccess() : settings.rightResize),
              event.flags.intersection([.maskAlternate, .maskCommand, .maskControl, .maskShift]).isEmpty,
              !CGEventSource.buttonState(.combinedSessionState, button: button == .left ? .right : .left),
              !CGEventSource.buttonState(.combinedSessionState, button: .center),
              let press = event.copy() else { return false }
        if button == .left, let cursor = NSCursor.currentSystem,
           (cursor.hotSpot.x > 8 || cursor.hotSpot.y > 8) { return false }
        let displays = DisplayArea.all()
        guard let display = DisplayArea.at(press.location, in: displays), display.usable.contains(press.location) else { return false }
        let candidate = Gesture(button: button, press: press, displays: displays, display: display)
        gesture = candidate
        resolve(candidate)
        // Capture/AX IPC never waits in this callback. A bounded buffer preserves
        // the original event sequence until detection accepts or declines it.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(180)) { [weak self, weak candidate] in
            guard let self, let candidate, self.gesture === candidate, candidate.writer == nil else { return }
            self.failOpen(candidate)
            Trace.write("reject candidate deadline")
        }
        return true
    }

    private func resolve(_ candidate: Gesture) {
        let point = candidate.press.location
        let radius = Int(settings.radius), tolerance = Int(settings.tolerance), band = settings.cornerBand
        let excluded = settings.excludedApps
        WindowAccess.resolutionQueue(at: point).async { [weak self, weak candidate] in
            guard let candidate else { return }
            let target = WindowAccess.resolve(point: point, resize: candidate.button == .right, exclusions: excluded, radius: radius)
            DispatchQueue.main.async { [weak self, candidate] in
                guard let self, self.gesture === candidate else { return }
                guard let target else { self.failOpen(candidate); return }
                if candidate.button == .right {
                    self.accept(candidate, target: target, band: band)
                    return
                }
                BackgroundSampler.check(target: target, point: point, radius: radius, tolerance: tolerance, display: candidate.display) { [weak self, weak candidate] uniform in
                    DispatchQueue.main.async {
                        guard let self, let candidate, self.gesture === candidate else { return }
                        if uniform { self.accept(candidate, target: target, band: band) }
                        else { self.failOpen(candidate) }
                    }
                }
            }
        }
    }

    private func accept(_ candidate: Gesture, target: WindowTarget, band: Double) {
        Trace.write("gesture accepted \(candidate.button)")
        candidate.target = target
        candidate.corner = candidate.button == .right ? Corner.select(at: candidate.press.location, in: target.initial, band: band) : nil
        if settings.nativeResize, let corner = candidate.corner {
            candidate.native = NativeResizeRoute(start: target.initial, corner: corner)
        }
        let writer = FrameWriter(target: target)
        candidate.writer = writer
        writer.onFailure = { [weak self, weak candidate] message in
            guard let self, let candidate else { return }
            self.status(message)
            if self.gesture === candidate {
                self.releaseNative(candidate)
                self.gesture = nil
                if candidate.intent.committed { self.swallowedButton = candidate.button }
                else { self.replay(candidate.events) }
            }
        }
        update(candidate)
    }

    private func update(_ active: Gesture) {
        guard let writer = active.writer, let target = active.target else { return }
        if active.intent.committed && !active.raised {
            active.raised = true
            NSRunningApplication(processIdentifier: target.pid)?.activate(options: [])
            target.accessQueue.async {
                _ = AXUIElementPerformAction(target.element, kAXRaiseAction as CFString)
                DispatchQueue.main.async { active.nativeReady = true }
            }
        }
        if (active.native != nil && !active.collisionInNativeSession) || active.nativeHandoff { return }
        if active.button == .left || active.intent.committed {
            guard active.intent.delta != .zero || active.changedGeometry else { return }
            active.changedGeometry = true
            writer.submit(active.request)
            status(active.button == .left ? "Moving \(target.name)" : "Resizing \(target.name)")
        }
    }

    private func failOpen(_ candidate: Gesture) {
        guard gesture === candidate else { return }
        gesture = nil
        replay(candidate.events)
    }

    private func finish(_ active: Gesture, cancel: Bool, replayClick: Bool) {
        guard gesture === active else { return }
        gesture = nil
        var releaseAfterDrain: CGEvent?
        if let native = active.native {
            if native.started {
                let release = active.press.copy()
                if let release { rewriteNative(release, type: .leftMouseUp, point: native.lastPoint) }
                if active.collisionInNativeSession { releaseAfterDrain = release }
                else if let release { replay([release]) }
                active.changedGeometry = true
            }
            active.native = nil
            if !cancel && native.started && !active.collisionInNativeSession { status("Ready"); return }
        }
        let events = active.events
        guard let writer = active.writer else {
            if replayClick { replay(events) }
            return
        }
        if !active.changedGeometry {
            if replayClick { replay(events.filter { $0.type != .leftMouseDragged && $0.type != .rightMouseDragged }) }
            return
        }
        if cancel {
            writer.submit(FrameRequest(start: active.target!.initial, delta: .zero, corner: nil,
                                       area: active.display.usable, restoring: true))
        } else { writer.submit(active.request) }
        if let releaseAfterDrain {
            drainingNativeRelease = releaseAfterDrain
            deferredReplay = []
        }
        if replayClick {
            deferredReplay = events.filter { $0.type != .leftMouseDragged && $0.type != .rightMouseDragged }
        }
        // Keep the writer alive until all pending writes are drained and a short
        // tentative move is restored before delivering its ordinary click.
        writer.finish { [self, writer] in
            _ = writer
            if releaseAfterDrain != nil, let release = drainingNativeRelease {
                replay([release])
                drainingNativeRelease = nil
                Trace.write("original native session ended after collision drain")
            }
            if replayClick || releaseAfterDrain != nil {
                let clicks = deferredReplay ?? []
                deferredReplay = nil
                replay(clicks)
            }
        }
        status("Ready")
    }

    private func replay(_ events: [CGEvent]) {
        for original in events {
            guard let copy = original.copy() else { continue }
            copy.setIntegerValueField(.eventSourceUserData, value: Self.replayTag)
            copy.post(tap: .cgSessionEventTap)
        }
    }

    private func rewriteNative(_ event: CGEvent, type: CGEventType, point: CGPoint) {
        event.type = type
        event.location = point
        event.flags.subtract([.maskControl, .maskAlternate, .maskShift, .maskCommand])
        event.setIntegerValueField(.mouseEventButtonNumber, value: 0)
        event.setIntegerValueField(.mouseEventClickState, value: 1)
    }

    /// Mutate the physical event in the tap, keeping the visible pointer where
    /// the user placed it. No timer, cursor warp, or per-frame AX size write.
    private func routeNativeDrag(_ active: Gesture, event: CGEvent) -> Bool {
        guard active.intent.committed, active.nativeReady, var native = active.native else { return true }
        if active.collisionInNativeSession { return true }
        // Start exactly one native session at the original corner, even when
        // the first committed sample is already beyond a display boundary.
        if native.started && native.needsPush(delta: active.intent.delta, area: active.display.usable) {
            active.collisionInNativeSession = true
            active.writer?.submit(active.request)
            Trace.write("collision continues original native session window=\(active.target?.windowID ?? 0)")
            return true
        }
        let type: CGEventType = native.started ? .leftMouseDragged : .leftMouseDown
        let point = native.nextPoint(delta: active.intent.delta)
        active.native = native
        active.changedGeometry = true
        rewriteNative(event, type: type, point: point)
        if type == .leftMouseDown { Trace.write("native resize began app=\(active.target?.bundleID ?? "") corner=\(native.corner)") }
        return false
    }
    private func releaseNative(_ active: Gesture) {
        guard let native = active.native, native.started else { return }
        if let release = active.press.copy() {
            rewriteNative(release, type: .leftMouseUp, point: native.lastPoint)
            replay([release])
        }
        active.native = nil
        active.collisionInNativeSession = false
    }
    private func upType(_ button: CGMouseButton) -> CGEventType { button == .left ? .leftMouseUp : .rightMouseUp }
    private func dragType(_ button: CGMouseButton) -> CGEventType { button == .left ? .leftMouseDragged : .rightMouseDragged }
}
