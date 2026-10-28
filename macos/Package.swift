// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Vaani", platforms: [.macOS(.v14)],
    products: [.executable(name: "Vaani", targets: ["Vaani"])],
    targets: [
        .target(name: "VaaniCore"),
        .executableTarget(name: "Vaani", dependencies: ["VaaniCore"]),
        .testTarget(name: "VaaniCoreTests", dependencies: ["VaaniCore"]),
        .testTarget(name: "VaaniTests", dependencies: ["Vaani", "VaaniCore"])
    ]
)
