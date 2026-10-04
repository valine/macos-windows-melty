import CoreGraphics

/// The native backend has separate position and size setters. Keep their ordering
/// here so the same transaction can be exercised against a display-clamping backend.
public protocol WindowFrameAccess {
    func readFrame() -> CGRect?
    func setPosition(_ point: CGPoint) -> Bool
    func setSize(_ size: CGSize) -> Bool
}

public enum FrameTransactionError: Error {
    case unavailable, positionRefused, sizeRefused, constraintsDoNotFit
}

public enum FrameTransaction {
    /// Use one final size, with the position write ordered to keep both steps on
    /// the display. An intermediate size is necessary only when neither order fits
    /// (for example, exchanging a full-height narrow window for a full-width one).
    @discardableResult
    public static func setFrame(_ frame: CGRect, area: CGRect? = nil,
                                using access: some WindowFrameAccess) throws -> CGRect {
        let desired = rounded(frame)
        guard let current = access.readFrame() else { throw FrameTransactionError.unavailable }
        let positionChanges = !close(current.origin, desired.origin)
        let sizeChanges = !close(current.size, desired.size)
        guard positionChanges || sizeChanges else { return current }
        var sizeWasLast = false
        func position() throws {
            guard access.setPosition(desired.origin) else { throw FrameTransactionError.positionRefused }
            sizeWasLast = false
        }
        func size(_ value: CGSize) throws {
            guard access.setSize(value) else { throw FrameTransactionError.sizeRefused }
            sizeWasLast = true
        }

        if !positionChanges {
            try size(desired.size)
        } else if !sizeChanges {
            try position()
        } else {
            let bounds = area ?? current.union(desired)
            let sizeFirst = CGRect(origin: current.origin, size: desired.size)
            let positionFirst = CGRect(origin: desired.origin, size: current.size)
            if bounds.contains(sizeFirst) {
                try size(desired.size)
                try position()
            } else if bounds.contains(positionFirst) {
                // In particular, bottom/right wall growth needs the origin moved
                // up/left first. Do not reintroduce the old display-size clamp.
                try position()
                try size(desired.size)
            } else {
                try size(CGSize(width: min(current.width, desired.width),
                                height: min(current.height, desired.height)))
                try position()
                try size(desired.size)
            }
        }
        guard let accepted = access.readFrame() else { throw FrameTransactionError.unavailable }
        // Correct genuine reanchoring only. Fractional pointer motion and native
        // rounding must not produce a second, slightly different position write.
        if sizeWasLast && !close(accepted.origin, desired.origin) {
            try position()
            guard let final = access.readFrame() else { throw FrameTransactionError.unavailable }
            return final
        }
        return accepted
    }

    @discardableResult
    public static func resize(start: CGRect, delta: CGPoint, corner: Corner, area: CGRect,
                              using access: some WindowFrameAccess) throws -> CGRect {
        guard let frame = WindowGeometry.resize(start: start, delta: delta, corner: corner, area: area) else {
            throw FrameTransactionError.constraintsDoNotFit
        }
        let desired = rounded(frame)
        guard let current = access.readFrame() else { throw FrameTransactionError.unavailable }

        // Probe the size at the CURRENT position whenever it fits there. In
        // particular, shrinking beyond an app minimum must not first move back
        // to the unconstrained origin and then jump to the minimum's push origin.
        // Only pre-position an axis when growth needs more display space.
        func stagingOrigin(_ origin: Double, _ span: Double, _ requestedOrigin: Double,
                           _ lo: Double, _ hi: Double) -> Double {
            origin >= lo && origin + span <= hi ? origin : requestedOrigin
        }
        let stage = CGPoint(x: stagingOrigin(current.minX, desired.width, desired.minX, area.minX, area.maxX),
                            y: stagingOrigin(current.minY, desired.height, desired.minY, area.minY, area.maxY))
        var changed = false
        if !close(current.origin, stage) {
            if !area.contains(CGRect(origin: stage, size: current.size)) {
                let smaller = CGSize(width: min(current.width, desired.width), height: min(current.height, desired.height))
                if !close(current.size, smaller) {
                    guard access.setSize(smaller) else { throw FrameTransactionError.sizeRefused }
                    changed = true
                }
            }
            guard access.setPosition(stage) else { throw FrameTransactionError.positionRefused }
            changed = true
        }
        if !close(current.size, desired.size) {
            guard access.setSize(desired.size) else { throw FrameTransactionError.sizeRefused }
            changed = true
        }
        guard let accepted = changed ? access.readFrame() : current else { throw FrameTransactionError.unavailable }
        // An app can acknowledge a setter while its animated geometry is still
        // changing. Never treat a changing readback as an intrinsic size limit.
        if !close(accepted.size, desired.size) {
            guard let settled = access.readFrame() else { throw FrameTransactionError.unavailable }
            guard close(accepted.size, settled.size) else { return settled }
        }
        // Infer intrinsic limits only AFTER moving to an origin where the desired
        // size fits. A clamp at the previous origin is not an app maximum.
        var minimum = CGSize(width: 1, height: 1)
        var maximum = CGSize(width: Double.greatestFiniteMagnitude, height: Double.greatestFiniteMagnitude)
        if accepted.width > desired.width + 0.5 { minimum.width = accepted.width }
        if accepted.height > desired.height + 0.5 { minimum.height = accepted.height }
        if accepted.width < desired.width - 0.5 { maximum.width = accepted.width }
        if accepted.height < desired.height - 0.5 { maximum.height = accepted.height }
        guard let constrained = WindowGeometry.resize(start: start, delta: delta, corner: corner, area: area,
                                                      minimum: minimum, maximum: maximum) else {
            _ = try? setFrame(start, area: area, using: access)
            throw FrameTransactionError.constraintsDoNotFit
        }
        // Apply the actual corner/constraint solution once, after size acceptance.
        // Don't run another full frame transaction or repeat the size request.
        let position = rounded(constrained).origin
        guard !close(accepted.origin, position) else { return accepted }
        guard access.setPosition(position) else { throw FrameTransactionError.positionRefused }
        guard let final = access.readFrame() else { throw FrameTransactionError.unavailable }
        return final
    }

    private static func close(_ a: CGPoint, _ b: CGPoint) -> Bool {
        abs(a.x - b.x) <= 0.5 && abs(a.y - b.y) <= 0.5
    }
    private static func close(_ a: CGSize, _ b: CGSize) -> Bool {
        abs(a.width - b.width) <= 0.5 && abs(a.height - b.height) <= 0.5
    }
    private static func rounded(_ frame: CGRect) -> CGRect {
        let x = frame.minX.rounded(), y = frame.minY.rounded()
        return CGRect(x: x, y: y, width: max(1, frame.maxX.rounded() - x),
                      height: max(1, frame.maxY.rounded() - y))
    }
}
