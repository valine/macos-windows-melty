// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeltyWindows",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "MeltyWindows", targets: ["MeltyWindows"])],
    targets: [
        .target(name: "WindowBehavior"),
        .executableTarget(name: "MeltyWindows", dependencies: ["WindowBehavior"]),
        .testTarget(name: "WindowBehaviorTests", dependencies: ["WindowBehavior"])
    ],
    swiftLanguageModes: [.v5]
)
