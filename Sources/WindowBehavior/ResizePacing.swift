/// Measures AX transaction latency, not the other app's private render loop.
/// Hysteresis avoids switching modes for one moderately late response.
public struct ResizePacing {
    public private(set) var slow = false
    private var slowSamples = 0
    private var fastSamples = 0
    private var estimate = 0.0
    public init() {}
    public mutating func record(seconds: Double) {
        estimate = estimate == 0 ? seconds : estimate * 0.75 + seconds * 0.25
        slowSamples = seconds >= 0.05 ? slowSamples + 1 : 0
        fastSamples = seconds < 0.025 ? fastSamples + 1 : 0
        if seconds >= 0.1 || slowSamples >= 2 { slow = true }
        if fastSamples >= 8 { slow = false }
    }
    /// Recovery time after completion, allowing the app to handle its own work.
    public var recovery: Double { slow ? min(0.1, max(0.016, estimate * 0.5)) : 0 }
}
