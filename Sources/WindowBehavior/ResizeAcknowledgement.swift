import CoreGraphics

public enum ResizeAcknowledgement {
    /// A timed-out setter may still have executed. Accept only a readback that
    /// reached the requested size or made measurable progress toward it.
    public static func applied(previous: CGSize?, requested: CGSize, observed: CGSize?) -> Bool {
        guard let observed, observed.width.isFinite, observed.height.isFinite,
              observed.width > 0, observed.height > 0 else { return false }
        func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) <= 0.5 }
        if close(observed.width, requested.width) && close(observed.height, requested.height) { return true }
        guard let previous else { return false }
        func toward(_ before: CGFloat, _ after: CGFloat, _ goal: CGFloat) -> Bool {
            after >= min(before, goal) - 0.5 && after <= max(before, goal) + 0.5
        }
        return toward(previous.width, observed.width, requested.width)
            && toward(previous.height, observed.height, requested.height)
            && (!close(previous.width, observed.width) || !close(previous.height, observed.height))
    }
}
