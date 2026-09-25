// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VoiceAssistant",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(name: "Swarm", path: "../../"),
    ],
    targets: [
        .executableTarget(
            name: "VoiceAssistant",
            dependencies: [
                .product(name: "Swarm", package: "Swarm"),
            ],
            path: "Sources/VoiceAssistant",
            exclude: ["Info.plist"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
    ]
)
