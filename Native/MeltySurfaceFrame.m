#import <AppKit/AppKit.h>
#include <math.h>

// Loaded by the cooperative app, never used for another process's windows.
// AppKit owns the transaction; the client closes it after its GL buffer swap.
@interface MeltySurfaceFrame : NSObject
@property(nonatomic, strong) NSWindow *window;
@end
@implementation MeltySurfaceFrame
@end

__attribute__((visibility("default"))) int MeltySurfaceFrameVersion(void) { return 1; }

__attribute__((visibility("default"))) void *MeltySurfaceFrameBegin(void *nativeWindow) {
    if (![NSThread isMainThread] || !nativeWindow) return NULL;
    NSWindow *window = (__bridge NSWindow *)nativeWindow;
    if (![window isKindOfClass:NSWindow.class] || window.inLiveResize) return NULL;
    MeltySurfaceFrame *frame = [MeltySurfaceFrame new];
    frame.window = window;
    [NSAnimationContext beginGrouping];
    NSAnimationContext.currentContext.duration = 0;
    NSAnimationContext.currentContext.allowsImplicitAnimation = NO;
    return (__bridge_retained void *)frame;
}

__attribute__((visibility("default"))) int MeltySurfaceFrameSet(void *token, double width, double height, double dx, double dy) {
    if (![NSThread isMainThread] || !token || !isfinite(width) || !isfinite(height)
        || !isfinite(dx) || !isfinite(dy) || width < 1 || height < 1) return 0;
    MeltySurfaceFrame *frame = (__bridge MeltySurfaceFrame *)token;
    NSWindow *window = frame.window;
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
    __unused MeltySurfaceFrame *frame = (__bridge_transfer MeltySurfaceFrame *)token;
    [NSAnimationContext endGrouping];
}
