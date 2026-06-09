// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "HearSub",
    platforms: [
        .macOS("26.0"),
    ],
    dependencies: [
        .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", from: "1.24.2"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "HearSub",
            dependencies: [
                .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/HearSubApp",
            resources: [
                .copy("Resources/AppIcon/AppIcon-512.png"),
                .copy("Resources/silero_vad.onnx"),
            ]
        ),
        .testTarget(
            name: "HearSubTests",
            dependencies: ["HearSub"],
            path: "Tests/HearSubTests"
        ),
    ]
)
