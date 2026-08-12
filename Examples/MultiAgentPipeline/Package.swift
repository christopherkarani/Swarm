// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MultiAgentPipeline",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(name: "Swarm", path: "../../", traits: ["Integrations"]),
    ],
    targets: [
        .executableTarget(
            name: "MultiAgentPipeline",
            dependencies: [
                .product(name: "Swarm", package: "Swarm"),
            ],
            path: "Sources/MultiAgentPipeline",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
    ]
)
