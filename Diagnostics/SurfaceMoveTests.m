// Exercise the actual helper with real AppKit events, without moving the pointer
// or sending events to another app. The public entry also checks physical state.
#import "../Native/MeltySurfaceFrame.m"

@interface MoveTestApp : NSApplication
@property NSEvent *releaseEvent;
@end
@implementation MoveTestApp
- (void)postEvent:(NSEvent *)event atStart:(BOOL)atStart { self.releaseEvent = event; }
@end

@interface MoveTestWindow : NSWindow
@property NSEvent *moveEvent;
@end
@implementation MoveTestWindow
- (void)performWindowDragWithEvent:(NSEvent *)event { self.moveEvent = event; }
@end

static NSEvent *press(NSWindow *window, NSInteger number) {
    return [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:NSMakePoint(45, 67)
        modifierFlags:0 timestamp:1 windowNumber:window.windowNumber context:nil
        eventNumber:number clickCount:1 pressure:1];
}

int main(void) { @autoreleasepool {
    MoveTestApp *app = [MoveTestApp sharedApplication];
    MoveTestWindow *first = [[MoveTestWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    MoveTestWindow *second = [[MoveTestWindow alloc] initWithContentRect:NSMakeRect(0, 0, 400, 300)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    NSEvent *original = press(first, 17);
    MeltySurfaceCapturePress(first, original, YES);
    assert(!MeltySurfaceStartMove(second, YES));
    assert(MeltySurfaceStartMove(first, YES));
    assert(first.moveEvent == original);
    assert(app.releaseEvent.type == NSEventTypeLeftMouseUp && app.releaseEvent.window == first);
    assert(app.releaseEvent.eventNumber == 17);
    assert(!MeltySurfaceStartMove(first, YES)); // exactly once per original press
    MeltySurfaceCapturePress(first, press(first, 18), YES);
    assert(!MeltySurfaceStartMove(first, NO)); // release before the render frame
    MeltySurfaceCapturePress(first, press(first, 19), YES);
    MeltySurfaceCapturePress(first, nil, NO);
    assert(!MeltySurfaceStartMove(first, YES));
    MeltySurfaceCapturePress(first, press(second, 20), YES);
    assert(!MeltySurfaceStartMove(first, YES));
    MeltySurfaceCapturePress(first, press(first, 21), YES);
    first.movable = NO;
    assert(!MeltySurfaceStartMove(first, YES));
    first.movable = YES;
    MeltySurfaceCapturePress(first, press(first, 22), YES);
    assert(MeltySurfaceStartMove(first, YES)); // rapid next gesture
    assert(first.moveEvent.eventNumber == 22);
    puts("PASS: original press, per-window ownership, release delivery, stale press refusal, rapid regrab");
} return 0; }
