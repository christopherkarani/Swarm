// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VoiceAgent",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(name: "Swarm", path: "../../"),
    ],
    targets: [
        .executableTarget(
            name: "VoiceAgent",
            dependencies: [
                .product(name: "Swarm", package: "Swarm"),
            ],
            path: "Sources/VoiceAgent",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
    ]
)
