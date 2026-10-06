// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Grove", platforms: [.macOS(.v15)], products: [
    .executable(name: "Grove", targets: ["Grove"])
], targets: [
    .target(name: "GroveCore"),
    .executableTarget(name: "Grove", dependencies: ["GroveCore"]),
    .testTarget(name: "GroveCoreTests", dependencies: ["GroveCore"]),
    .testTarget(name: "GroveTests", dependencies: ["Grove", "GroveCore"])
], swiftLanguageModes: [.v6])
