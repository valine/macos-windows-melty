// Capture only the probe's own window. No desktop capture or TCC prompt.
#import <AppKit/AppKit.h>
#import <ScreenCaptureKit/ScreenCaptureKit.h>
#include <stdatomic.h>
#include <stdio.h>

static FILE *outputFile;
static int captured, mismatched;
static atomic_int ready, stopped;
static SCStream *activeStream;
static dispatch_queue_t captureQueue;

@interface MeltyPresentationCapture : NSObject <SCStreamOutput>
@end
@implementation MeltyPresentationCapture
- (void)stream:(SCStream *)stream didOutputSampleBuffer:(CMSampleBufferRef)sample
        ofType:(SCStreamOutputType)type {
    if (type != SCStreamOutputTypeScreen || !CMSampleBufferIsValid(sample)) return;
    NSArray *attachments = (__bridge NSArray *)CMSampleBufferGetSampleAttachmentsArray(sample, NO);
    NSDictionary *info = attachments.firstObject;
    if ([info[SCStreamFrameInfoStatus] intValue] != SCFrameStatusComplete) return;
    CVPixelBufferRef buffer = CMSampleBufferGetImageBuffer(sample);
    if (!buffer) return;
    CVPixelBufferLockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
    int width = (int)CVPixelBufferGetWidth(buffer), height = (int)CVPixelBufferGetHeight(buffer);
    size_t stride = CVPixelBufferGetBytesPerRow(buffer);
    unsigned char *pixels = CVPixelBufferGetBaseAddress(buffer);
    int left = width, top = height, right = -1, bottom = -1;
    for (int y = 0; y < height; y++) {
        unsigned char *row = pixels + y * stride;
        for (int x = 0; x < width; x++) {
            unsigned char *p = row + 4 * x;
            if (p[1] > 180 && p[2] < 50 && p[0] < 50) {
                left = MIN(left, x); right = MAX(right, x);
                top = MIN(top, y); bottom = MAX(bottom, y);
            }
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, kCVPixelBufferLock_ReadOnly);
    int squareWidth = right - left + 1, squareHeight = bottom - top + 1;
    captured++;
    if (right < 0 || abs(squareWidth - 200) > 1 || abs(squareHeight - 200) > 1) mismatched++;
    NSDictionary *record = @{
        @"capture": @(captured), @"time": @(CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))),
        @"square": @[@(left), @(top), @(squareWidth), @(squareHeight)],
        @"content_scale": info[SCStreamFrameInfoContentScale] ?: @0,
        @"content": info[SCStreamFrameInfoContentRect] ?: @{}
    };
    NSData *json = [NSJSONSerialization dataWithJSONObject:record options:0 error:nil];
    fwrite(json.bytes, 1, json.length, outputFile);
    fputc('\n', outputFile);
}
@end

static MeltyPresentationCapture *captureOutput;

int MeltyPresentationReady(void) { return atomic_load(&ready); }

void MeltyPresentationStart(void *nativeWindow, const char *path) {
    NSWindow *native = (__bridge NSWindow *)nativeWindow;
    NSInteger windowNumber = native.windowNumber;
    outputFile = fopen(path, "w");
    if (!outputFile) { atomic_store(&ready, -1); return; }
    captureOutput = [MeltyPresentationCapture new];
    captureQueue = dispatch_queue_create("org.melty.presentation-capture", DISPATCH_QUEUE_SERIAL);
    [SCShareableContent getCurrentProcessShareableContentWithCompletionHandler:^(SCShareableContent *content, NSError *error) {
        if (error) { atomic_store(&ready, -1); return; }
        SCWindow *target = nil;
        for (SCWindow *candidate in content.windows) {
            if (candidate.windowID == windowNumber) target = candidate;
        }
        if (!target) { atomic_store(&ready, -1); return; }
        SCContentFilter *filter = [[SCContentFilter alloc] initWithDesktopIndependentWindow:target];
        SCStreamConfiguration *config = [SCStreamConfiguration new];
        // Larger than every probe size, including Retina; never downscale.
        config.width = 4200; config.height = 3200;
        config.scalesToFit = NO; config.showsCursor = NO;
        config.minimumFrameInterval = kCMTimeZero; config.queueDepth = 5;
        config.pixelFormat = kCVPixelFormatType_32BGRA;
        config.ignoreShadowsSingleWindow = YES;
        activeStream = [[SCStream alloc] initWithFilter:filter configuration:config delegate:nil];
        NSError *addError = nil;
        [activeStream addStreamOutput:captureOutput type:SCStreamOutputTypeScreen
                  sampleHandlerQueue:captureQueue error:&addError];
        if (addError) { atomic_store(&ready, -1); return; }
        [activeStream startCaptureWithCompletionHandler:^(NSError *startError) {
            atomic_store(&ready, startError ? -1 : 1);
        }];
    }];
}

void MeltyPresentationStop(void) {
    [activeStream stopCaptureWithCompletionHandler:^(NSError *error) { atomic_store(&stopped, 1); }];
}

int MeltyPresentationStopped(void) { return atomic_load(&stopped); }

int MeltyPresentationFinish(void) {
    dispatch_sync(captureQueue, ^{});
    fclose(outputFile);
    printf("captures=%d mismatches=%d\n", captured, mismatched);
    return captured < 120 ? -1 : mismatched;
}
