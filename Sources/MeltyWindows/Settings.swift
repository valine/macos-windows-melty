import AppKit

final class Settings: ObservableObject {
    static let shared = Settings()
    private let defaults = UserDefaults.standard
    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "enabled") } }
    @Published var leftMove: Bool { didSet { defaults.set(leftMove, forKey: "leftMove") } }
    @Published var rightResize: Bool { didSet { defaults.set(rightResize, forKey: "rightResize") } }
    @Published var radius: Double { didSet { defaults.set(radius, forKey: "radius") } }
    @Published var tolerance: Double { didSet { defaults.set(tolerance, forKey: "tolerance") } }
    @Published var cornerBand: Double { didSet { defaults.set(cornerBand, forKey: "cornerBand") } }
    @Published var continueAtEdge: Bool { didSet { defaults.set(continueAtEdge, forKey: "continueAtEdge") } }
    @Published var exclusions: String { didSet { defaults.set(exclusions, forKey: "exclusions") } }

    private init() {
        defaults.register(defaults: ["enabled": true, "leftMove": true, "rightResize": true,
                                    "radius": 52.0, "tolerance": 29.0, "cornerBand": 400.0,
                                    "continueAtEdge": true,
                                    "exclusions": "org.meltygui.code-editor\ncom.apple.Terminal\ncom.googlecode.iterm2"])
        enabled = defaults.bool(forKey: "enabled")
        leftMove = defaults.bool(forKey: "leftMove")
        rightResize = defaults.bool(forKey: "rightResize")
        radius = defaults.double(forKey: "radius")
        tolerance = defaults.double(forKey: "tolerance")
        cornerBand = defaults.double(forKey: "cornerBand")
        continueAtEdge = defaults.bool(forKey: "continueAtEdge")
        exclusions = defaults.string(forKey: "exclusions") ?? ""
    }

    var excludedApps: Set<String> {
        Set(exclusions.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty })
    }
}

struct DisplayArea {
    let frame: CGRect
    let usable: CGRect
    let scale: Double

    static func all() -> [DisplayArea] {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        func flip(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
        }
        return NSScreen.screens.map { DisplayArea(frame: flip($0.frame), usable: flip($0.visibleFrame), scale: $0.backingScaleFactor) }
    }

    static func at(_ point: CGPoint, in displays: [DisplayArea]) -> DisplayArea? {
        displays.first { $0.frame.contains(point) } ?? displays.min {
            hypot($0.frame.midX - point.x, $0.frame.midY - point.y) < hypot($1.frame.midX - point.x, $1.frame.midY - point.y)
        }
    }
}
