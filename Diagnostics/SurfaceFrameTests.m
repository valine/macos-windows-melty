#import <AppKit/AppKit.h>
extern void *MeltySurfaceFrameBegin(void *);
extern int MeltySurfaceFrameSet(void *, double, double, double, double);
extern void MeltySurfaceFrameEnd(void *);
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(300, 300, 800, 600)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
    NSAnimationContext *outer = NSAnimationContext.currentContext;
    outer.duration = 0.73;
    NSRect initial = [window contentRectForFrameRect:window.frame];
    void *token = MeltySurfaceFrameBegin((__bridge void *)window);

    if (!token) return 1;
    assert(window.contentView.layerContentsPlacement == NSViewLayerContentsPlacementTopLeft);
    assert(NSAnimationContext.currentContext.duration == 0);
    assert(!NSAnimationContext.currentContext.allowsImplicitAnimation);
    assert(!MeltySurfaceFrameSet(token, -1, 200, 0, 0));
    assert(MeltySurfaceFrameSet(token, 900, 700, -100, -100));
    assert(window.contentView.layerContentsPlacement == NSViewLayerContentsPlacementTopLeft);
    NSRect grown = [window contentRectForFrameRect:window.frame];
    assert(grown.origin.x == initial.origin.x-100 && NSMaxY(grown) == NSMaxY(initial)+100);
    assert(grown.size.width == 900 && grown.size.height == 700);
    assert(MeltySurfaceFrameSet(token, 800, 600, 100, 100));
    assert(NSEqualRects([window contentRectForFrameRect:window.frame], initial));
    MeltySurfaceFrameEnd(token);
    assert(window.contentView.layerContentsPlacement == NSViewLayerContentsPlacementTopLeft);
    assert(fabs(NSAnimationContext.currentContext.duration - 0.73) < 1e-6);
    MeltySurfaceFrameEnd(NULL);
    puts("PASS: native combined geometry, reversal, invalid-size refusal, balanced zero-duration transaction");
} return 0; }
