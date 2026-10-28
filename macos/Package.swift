// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Vaani", platforms: [.macOS(.v14)],
    products: [.executable(name: "Vaani", targets: ["Vaani"])],
    targets: [
        .target(name: "CRNNoise", path: "ThirdParty/rnnoise", exclude: ["COPYING", "README.vaani.md"],
                sources: ["src"], publicHeadersPath: "include",
                cSettings: [.define("USE_WEIGHTS_FILE"), .define("RNNOISE_BUILD"), .headerSearchPath("src")]),
        .target(name: "VaaniCore", dependencies: ["CRNNoise"], resources: [.copy("Resources/rnnoise-model.bin")]),
        .executableTarget(name: "Vaani", dependencies: ["VaaniCore"]),
        .testTarget(name: "VaaniCoreTests", dependencies: ["VaaniCore"]),
        .testTarget(name: "VaaniTests", dependencies: ["Vaani", "VaaniCore"])
    ]
)
