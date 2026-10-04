import AppKit
import ScreenCaptureKit
import WindowBehavior

enum BackgroundSampler {
    static func check(target: WindowTarget, point: CGPoint, radius: Int, tolerance: Int,
                      display: DisplayArea, completion: @escaping (Bool) -> Void) {
        guard CGPreflightScreenCaptureAccess(), target.sampleIsUnobscured else { completion(false); return }
        let rect = WindowGeometry.sampleRect(at: point, frame: target.initial, radius: radius)
        // An offscreen part of a sample has no meaningful app pixels.
        guard display.frame.contains(rect), rect.width > 0, rect.height > 0 else { completion(false); return }
        let config = SCScreenshotConfiguration()
        config.showsCursor = false
        config.dynamicRange = .sdr
        config.width = max(1, Int((rect.width * display.scale).rounded()))
        config.height = max(1, Int((rect.height * display.scale).rounded()))
        // No fileURL: only a small, transient crop is captured, never saved.
        SCScreenshotManager.captureScreenshot(rect: rect, configuration: config) { output, error in
            Trace.write("capture returned image=\(output?.sdrImage != nil) error=\(String(describing: error))")
            let image = output?.sdrImage
            WindowAccess.queue.async {
                guard error == nil, let image, WindowAccess.isStillAtStart(target) else { completion(false); return }
                let width = image.width, height = image.height, rowBytes = width * 4
                var pixels = [UInt8](repeating: 0, count: rowBytes * height)
                let ok = pixels.withUnsafeMutableBytes { bytes -> Bool in
                    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                          let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                                  bytesPerRow: rowBytes, space: space,
                                                  bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                    return true
                }
                guard ok else { completion(false); return }
                let x = max(0, min(width - 1, Int(((point.x - rect.minX) * Double(width) / rect.width).rounded())))
                let y = max(0, min(height - 1, Int(((point.y - rect.minY) * Double(height) / rect.height).rounded())))
                let uniform = UniformPixels.check(pixels, width: width, height: height, rowBytes: rowBytes,
                                                  referenceX: x, referenceY: y, tolerance: tolerance)
                Trace.write("background uniform=\(uniform) sample=\(width)x\(height)")
                completion(uniform)
            }
        }
    }
}
