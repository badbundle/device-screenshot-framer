// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "device-screenshot-framer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "framer", targets: ["framer"]),
        .library(name: "FramerCore", targets: ["FramerCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "FramerCore",
            linkerSettings: [
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreText"),
                .linkedFramework("ImageIO"),
            ]
        ),
        .executableTarget(
            name: "framer",
            dependencies: [
                "FramerCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "FramerCoreTests",
            dependencies: ["FramerCore"]
        ),
    ]
)
