// swift-tools-version: 6.2
import PackageDescription
import CompilerPluginSupport
import Foundation
let includeDemo = ProcessInfo.processInfo.environment["SWARM_INCLUDE_DEMO"] == "1"

var packageProducts: [Product] = [
    .library(name: "Swarm", targets: ["Swarm"]),
    .library(name: "SwarmMembrane", targets: ["SwarmMembrane"]),
    .library(name: "SwarmMCP", targets: ["SwarmMCP"]),
]

if includeDemo {
    packageProducts.append(.executable(name: "SwarmDemo", targets: ["SwarmDemo"]))
    packageProducts.append(.executable(name: "ContextBenchmark", targets: ["ContextBenchmark"]))
    packageProducts.append(.executable(name: "SwarmMCPServerDemo", targets: ["SwarmMCPServerDemo"]))
}

var packageDependencies: [Package.Dependency] = [
    // swift-syntax range is intentionally widened to include 601/602 lines.
    //
    // Background: Xcode 26 (Swift 6.2.x) ships implicit SwiftPM prebuilts for
    // swift-syntax via the swiftlang "MacroSupport" prebuilt server. The 600.0.1
    // prebuilt is built against an older macOS SDK and fails to load on consumer
    // machines with "SDK does not match" warnings followed by
    // "Unable to find module dependency: 'SwiftSyntax'" errors. That prebuilt
    // download cannot be disabled from a consumer project (SWIFT_USE_PREBUILT_MACROS=NO,
    // IDESwiftPackageEnablePrebuilts=NO, SWIFTPM_DISABLE_PREBUILTS=1 and
    // -skipMacroValidation all fail to suppress it). Widening the range here lets
    // SwiftPM resolve to 601+ on Swift 6.2 toolchains, which does not ship the
    // broken prebuilt.
    .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0"..<"603.0.0"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.10.1"),
    .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
    .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.13.2"),
    // Production graph must resolve to the published tag set that is known to build together.
    .package(url: "https://github.com/gungorbasa/Wax.git", exact: "0.1.22"),
    .package(
        url: "https://github.com/christopherkarani/Conduit",
        exact: "0.3.14",
        traits: [
            .trait(name: "OpenAI"),
            .trait(name: "OpenRouter"),
            .trait(name: "Anthropic"),
            .trait(name: "MLX"),
        ]
    ),
    .package(url: "https://github.com/christopherkarani/ContextCore.git", exact: "1.0.0"),
    .package(url: "https://github.com/christopherkarani/Membrane", exact: "0.1.3"),
    .package(url: "https://github.com/christopherkarani/Hive", exact: "0.1.9"),
]

var swarmDependencies: [Target.Dependency] = [
    "SwarmMacros",
    .product(name: "Logging", package: "swift-log"),
    .product(name: "SwiftSoup", package: "SwiftSoup"),
    .product(name: "Wax", package: "Wax"),
    .product(name: "Conduit", package: "Conduit"),
    .product(name: "ConduitAdvanced", package: "Conduit"),
    .product(name: "ContextCore", package: "ContextCore"),
    .product(name: "HiveCore", package: "Hive"),
    .product(name: "Membrane", package: "Membrane"),
    .product(name: "MembraneCore", package: "Membrane"),
    .product(name: "MembraneHive", package: "Membrane")
]

var swarmSwiftSettings: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
    .define("SWARM_HIVE", .when(traits: ["hive"])),
]

var packageTargets: [Target] = [
    // MARK: - Macro Implementation (Compiler Plugin)
    .macro(
        name: "SwarmMacros",
        dependencies: [
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            .product(name: "SwiftSyntaxBuilder", package: "swift-syntax")
        ],
        swiftSettings: [
            .enableExperimentalFeature("StrictConcurrency")
        ]
    ),

    // MARK: - Main Library
    .target(
        name: "Swarm",
        dependencies: swarmDependencies,
        swiftSettings: swarmSwiftSettings
    ),
    .target(
        name: "SwarmMembrane",
        dependencies: [
            "Swarm",
        ],
        path: "Sources/SwarmMembrane",
        swiftSettings: swarmSwiftSettings
    ),
    .target(
        name: "SwarmMCP",
        dependencies: [
            "Swarm",
            .product(name: "MCP", package: "swift-sdk"),
        ],
        swiftSettings: swarmSwiftSettings
    ),
    .target(
        name: "SwarmCapabilityShowcaseSupport",
        dependencies: [
            "Swarm",
            "SwarmMCP",
        ],
        swiftSettings: swarmSwiftSettings
    ),
    .executableTarget(
        name: "SwarmCapabilityShowcase",
        dependencies: [
            "SwarmCapabilityShowcaseSupport",
        ],
        swiftSettings: [
            .enableExperimentalFeature("StrictConcurrency")
        ]
    ),

    // MARK: - Tests
    .testTarget(
        name: "SwarmTests",
        dependencies: {
            let dependencies: [Target.Dependency] = [
                "Swarm",
                "SwarmMCP",
                .product(name: "Conduit", package: "Conduit"),
                .product(name: "ConduitAdvanced", package: "Conduit"),
                .product(name: "Membrane", package: "Membrane"),
                .product(name: "MembraneCore", package: "Membrane"),
            ]
            return dependencies
        }(),
        resources: [
            .copy("Guardrails/INTEGRATION_TEST_SUMMARY.md"),
            .copy("Guardrails/QUICK_REFERENCE.md")
        ],
        swiftSettings: swarmSwiftSettings
    ),
    .testTarget(
        name: "HiveSwarmTests",
        dependencies: [
            "Swarm",
            .product(name: "HiveCore", package: "Hive")
        ],
        swiftSettings: swarmSwiftSettings
    ),
    .testTarget(
        name: "SwarmMacrosTests",
        dependencies: [
            "SwarmMacros",
            .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
        ],
        swiftSettings: [
            .enableExperimentalFeature("StrictConcurrency")
        ]
    ),
    .testTarget(
        name: "SwarmCapabilityShowcaseTests",
        dependencies: [
            "SwarmCapabilityShowcaseSupport",
        ],
        swiftSettings: [
            .enableExperimentalFeature("StrictConcurrency")
        ]
    )
]

if includeDemo {
    packageTargets.append(
        .executableTarget(
            name: "SwarmDemo",
            dependencies: ["Swarm"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    )

    packageTargets.append(
        .executableTarget(
            name: "ContextBenchmark",
            dependencies: ["Swarm"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    )

    packageTargets.append(
        .executableTarget(
            name: "SwarmMCPServerDemo",
            dependencies: [
                "Swarm",
                "SwarmMCP",
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    )
}

let package = Package(
    name: "Swarm",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .tvOS(.v26),
    ],
    products: packageProducts,
    traits: [
        .trait(
            name: "hive",
            description: "Enable Hive-backed workflow and runtime integration features."
        ),
    ],
    dependencies: packageDependencies,
    targets: packageTargets
)
