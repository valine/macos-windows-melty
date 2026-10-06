#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#include <math.h>
#include <stdlib.h>

// Loaded by the cooperative app, never used for another process's windows.
// AppKit owns the transaction; the client closes it after its GL buffer swap.
// A C token avoids Objective-C class-name collisions when an already-running
// client loads a newer helper alongside the old build.
typedef struct {
    CFTypeRef window;
} MeltySurfaceFrame;

__attribute__((visibility("default"))) int MeltySurfaceFrameVersion(void) { return 1; }

// Keep the original press on its own window. MeltyGUI arbitrates the drag on
// a later frame, after controls/dividers have had first refusal. Never infer
// a movable region from pixels, and never enable whole-view background dragging.
static char MeltySurfaceMovePressKey;

static void MeltySurfaceCapturePress(NSWindow *window, NSEvent *event, BOOL down) {
    if (!down || event.type != NSEventTypeLeftMouseDown || event.window != window) {
        objc_setAssociatedObject(window, &MeltySurfaceMovePressKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    objc_setAssociatedObject(window, &MeltySurfaceMovePressKey, event, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

__attribute__((visibility("default"))) void MeltySurfaceMoveCapture(void *nativeWindow, int down) {
    if (![NSThread isMainThread] || !nativeWindow) return;
    NSWindow *window = (__bridge NSWindow *)nativeWindow;
    if (![window isKindOfClass:NSWindow.class]) return;
    MeltySurfaceCapturePress(window, NSApp.currentEvent, down != 0);
}

static int MeltySurfaceStartMove(NSWindow *window, BOOL buttonDown) {
    NSEvent *press = objc_getAssociatedObject(window, &MeltySurfaceMovePressKey);
    objc_setAssociatedObject(window, &MeltySurfaceMovePressKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (!press || !buttonDown || !window.movable || window.inLiveResize
        || (window.styleMask & NSWindowStyleMaskFullScreen)) return 0;
    [window performWindowDragWithEvent:press];
    // WindowServer owns the remaining gesture and may consume mouse-up.
    // Deliver a release only to this application's original GLFW window so
    // both its event queue and glfwGetMouseButton stop reporting a stuck press.
    NSEvent *release = [NSEvent mouseEventWithType:NSEventTypeLeftMouseUp
        location:press.locationInWindow modifierFlags:press.modifierFlags
        timestamp:NSProcessInfo.processInfo.systemUptime windowNumber:window.windowNumber
        context:nil eventNumber:press.eventNumber clickCount:press.clickCount pressure:0];
    [NSApp postEvent:release atStart:YES];
    return 1;
}

__attribute__((visibility("default"))) int MeltySurfaceMoveBegin(void *nativeWindow) {
    if (![NSThread isMainThread] || !nativeWindow) return 0;
    NSWindow *window = (__bridge NSWindow *)nativeWindow;
    if (![window isKindOfClass:NSWindow.class]) return 0;
    return MeltySurfaceStartMove(window, (NSEvent.pressedMouseButtons & 1) != 0);
}

__attribute__((visibility("default"))) void *MeltySurfaceFrameBegin(void *nativeWindow) {
    if (![NSThread isMainThread] || !nativeWindow) return NULL;
    NSWindow *window = (__bridge NSWindow *)nativeWindow;
    if (![window isKindOfClass:NSWindow.class] || window.inLiveResize) return NULL;
    // Establish placement before the first geometry transaction, including a
    // frame with no resize. Changing it together with the first new size can
    // still expose one scaled buffer while that layer update is pending.
    // AppKit otherwise scales the previous NSGL buffer to the new frame.
    if (window.contentView.layerContentsPlacement != NSViewLayerContentsPlacementTopLeft) {
        window.contentView.layerContentsPlacement = NSViewLayerContentsPlacementTopLeft;
    }
    MeltySurfaceFrame *frame = calloc(1, sizeof(*frame));
    if (!frame) return NULL;
    frame->window = CFBridgingRetain(window);
    [NSAnimationContext beginGrouping];
    NSAnimationContext.currentContext.duration = 0;
    NSAnimationContext.currentContext.allowsImplicitAnimation = NO;
    return frame;
}

__attribute__((visibility("default"))) int MeltySurfaceFrameSet(void *token, double width, double height, double dx, double dy) {
    if (![NSThread isMainThread] || !token || !isfinite(width) || !isfinite(height)
        || !isfinite(dx) || !isfinite(dy) || width < 1 || height < 1) return 0;
    MeltySurfaceFrame *frame = token;
    NSWindow *window = (__bridge NSWindow *)frame->window;
    NSRect content = [window contentRectForFrameRect:window.frame];
    // GLFW uses top-left content coordinates; AppKit uses bottom-left frames.
    content.origin.x += dx;
    content.origin.y += content.size.height - height - dy;
    content.size = NSMakeSize(width, height);
    NSRect target = [window frameRectForContentRect:content];
    if (!NSEqualRects(target, window.frame)) {
        // One geometry change without forcing an intermediate display.
        // GLFW's existing NSWindow delegate updates drawable/size.
        [window setFrame:target display:NO];
    }
    return 1;
}

__attribute__((visibility("default"))) void MeltySurfaceFrameEnd(void *token) {
    if (!token) return;
    NSCAssert([NSThread isMainThread], @"Surface transactions end on the render thread");
    MeltySurfaceFrame *frame = token;
    [NSAnimationContext endGrouping];
    // Keep placement: the compositor consumes the submitted buffer later.
    CFRelease(frame->window);
    free(frame);
}
