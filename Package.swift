// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "neowall",
    platforms: [.macOS(.v14)],
    dependencies: [
        // In-app updates. Ships as a binary framework; `make app` embeds it in the bundle.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(name: "NeowallCore"),
        .executableTarget(
            name: "neowall",
            dependencies: ["NeowallCore", .product(name: "Sparkle", package: "Sparkle")]
        ),
        .testTarget(name: "NeowallCoreTests", dependencies: ["NeowallCore"]),
    ]
)
