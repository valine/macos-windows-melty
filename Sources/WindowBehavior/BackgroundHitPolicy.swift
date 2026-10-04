/// Walk from the hit element toward its owning window. A browser's outer tab
/// container wraps page content; a tab widget *inside* a page remains protected.
public struct BackgroundHitPolicy {
    private var isHit = true
    private var crossedWebArea = false
    private static let allowedHits: Set<String> = [
        "AXWindow", "AXGroup", "AXLayoutArea", "AXScrollArea", "AXWebArea", "AXSplitGroup", "AXUnknown"
    ]
    private static let protected: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXTextField", "AXTextArea", "AXComboBox", "AXPopUpButton",
        "AXSlider", "AXScrollBar", "AXSplitter", "AXLink", "AXMenu", "AXMenuItem", "AXTable", "AXOutline", "AXList", "AXTabGroup"
    ]

    public init() {}

    public mutating func permits(role: String) -> Bool {
        if isHit && !Self.allowedHits.contains(role) { return false }
        isHit = false
        if Self.protected.contains(role) && !(role == "AXTabGroup" && crossedWebArea) { return false }
        if role == "AXWebArea" { crossedWebArea = true }
        return true
    }
}
