// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Grove", platforms: [.macOS(.v15)], products: [
    .executable(name: "Grove", targets: ["Grove"])
], dependencies: [
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
], targets: [
    .target(name: "GroveCore"),
    .executableTarget(name: "Grove", dependencies: ["GroveCore", .product(name: "Sparkle", package: "Sparkle")],
                      linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
    .testTarget(name: "GroveCoreTests", dependencies: ["GroveCore"]),
    .testTarget(name: "GroveTests", dependencies: ["Grove", "GroveCore"])
], swiftLanguageModes: [.v6])
