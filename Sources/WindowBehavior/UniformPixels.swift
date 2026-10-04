import Foundation

public enum UniformPixels {
    /// Compare *every* RGBA channel with the pixel under the press, not with an
    /// average or a few sparse samples. Row padding must never be sampled.
    public static func check(_ bytes: [UInt8], width: Int, height: Int, rowBytes: Int,
                             referenceX: Int, referenceY: Int, tolerance: Int) -> Bool {
        guard width > 0, height > 0, rowBytes >= width * 4,
              bytes.count >= rowBytes * height,
              (0..<width).contains(referenceX), (0..<height).contains(referenceY) else { return false }
        let reference = referenceY * rowBytes + referenceX * 4
        let tolerance = max(0, min(255, tolerance))
        // A missing/protected capture may be fully transparent; it is not empty app space.
        guard bytes[reference + 3] == 255 else { return false }
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * rowBytes + x * 4
                for channel in 0..<4 where abs(Int(bytes[offset + channel]) - Int(bytes[reference + channel])) > tolerance {
                    return false
                }
            }
        }
        return true
    }
}
