/// Walk from the hit element toward its owning window. A browser's outer tab
/// container wraps page content; a tab widget *inside* a page remains protected.
public struct BackgroundHitPolicy {
    private var isHit = true
    private var crossedWebArea = false
    private let bundleID: String
    public private(set) var requiresUniformPixels = true
    private static let allowedHits: Set<String> = [
        "AXWindow", "AXGroup", "AXLayoutArea", "AXScrollArea", "AXWebArea", "AXSplitGroup", "AXUnknown"
    ]
    private static let protected: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXTextField", "AXTextArea", "AXComboBox", "AXPopUpButton",
        "AXSlider", "AXScrollBar", "AXSplitter", "AXLink", "AXMenu", "AXMenuItem", "AXTable", "AXOutline", "AXList", "AXTabGroup"
    ]

    public init(bundleID: String = "") { self.bundleID = bundleID }

    public mutating func permits(role: String, identifier: String? = nil) -> Bool {
        // Only a direct hit on the collection's empty surface qualifies.
        // Descendants (file rows, message bubbles, and controls) retain their
        // own drags even when they have the same collection as an ancestor.
        if isHit {
            let finderBackground = bundleID == "com.apple.finder"
                && ["AXOutline", "AXList", "AXTable"].contains(role)
            let transcriptBackground = bundleID == "com.apple.iChat"
                && identifier == "TranscriptCollectionView"
                && ["AXGroup", "AXLayoutArea", "AXList", "AXScrollArea"].contains(role)
            if finderBackground || transcriptBackground {
                isHit = false
                requiresUniformPixels = !transcriptBackground
                return true
            }
        }
        if isHit && !Self.allowedHits.contains(role) { return false }
        isHit = false
        if Self.protected.contains(role) && !(role == "AXTabGroup" && crossedWebArea) { return false }
        if role == "AXWebArea" { crossedWebArea = true }
        return true
    }
}
