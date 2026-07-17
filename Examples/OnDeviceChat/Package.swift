// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OnDeviceChat",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(name: "Swarm", path: "../../"),
    ],
    targets: [
        .executableTarget(
            name: "OnDeviceChat",
            dependencies: [
                .product(name: "Swarm", package: "Swarm"),
            ],
            path: "Sources/OnDeviceChat",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency"),
            ]
        ),
    ]
)
