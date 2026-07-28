// swift-tools-version: 6.2
import PackageDescription
import CompilerPluginSupport
import Foundation
let includeDemo = ProcessInfo.processInfo.environment["SWARM_INCLUDE_DEMO"] == "1"
let coreOnly = ProcessInfo.processInfo.environment["SWARM_CORE_ONLY"] == "1"

var packageProducts: [Product] = [
    .library(name: "Swarm", targets: ["Swarm"]),
    .library(name: "SwarmOpenTelemetry", targets: ["SwarmOpenTelemetry"]),
    .library(name: "SwarmMembrane", targets: ["SwarmMembrane"]),
    .library(name: "SwarmMCP", targets: ["SwarmMCP"]),
]

if includeDemo {
    packageProducts.append(.executable(name: "SwarmDemo", targets: ["SwarmDemo"]))
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
    // broken prebuilt. Keep the upper bound below 603 for package-graph stability
    // with the current Membrane/Hive integration pin set.
    .package(url: "https://github.com/swiftlang/swift-syntax.git", "600.0.0"..<"603.0.0"),
    .package(url: "https://github.com/apple/swift-log.git", from: "1.12.0"),
    .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1"),
    .package(url: "https://github.com/open-telemetry/opentelemetry-swift-core.git", from: "2.4.1"),
    .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.13.5"),
]

// Integrations trait: opt-in graph/memory/web/Hive paths (off by default).
// Roadmap: Hive, Membrane, and ContextCore become in-tree Sources/ targets
// (local folders linked only when Integrations is on). Wax stays remote for now.
// Remotes below are temporary until that vendor lands.
let integrationTrait = "Integrations"
if !coreOnly {
    packageDependencies += [
        // Temporary remotes until Hive/Membrane/ContextCore are vendored under Sources/.
        // Wax remains an external package + trait-gated product dependency.
        .package(url: "https://github.com/christopherkarani/Wax.git", exact: "0.1.23"),
        .package(url: "https://github.com/christopherkarani/ContextCore.git", exact: "1.0.0"),
        .package(url: "https://github.com/christopherkarani/Membrane", exact: "0.1.4"),
        .package(url: "https://github.com/christopherkarani/Hive", exact: "0.2.1"),
    ]
}

var swarmDependencies: [Target.Dependency] = [
    "SwarmMacros",
    .product(name: "Logging", package: "swift-log"),
    // HTML parsing for web helpers; only linked when Integrations is enabled.
    .product(name: "SwiftSoup", package: "SwiftSoup", condition: .when(traits: [integrationTrait])),
]

var swarmSwiftSettings: [SwiftSetting] = [
    .enableExperimentalFeature("StrictConcurrency"),
]

if !coreOnly {
    swarmDependencies += [
        .product(name: "Wax", package: "Wax", condition: .when(traits: [integrationTrait])),
        .product(name: "ContextCore", package: "ContextCore", condition: .when(traits: [integrationTrait])),
        .product(name: "HiveCore", package: "Hive", condition: .when(traits: [integrationTrait])),
        .product(name: "Membrane", package: "Membrane", condition: .when(traits: [integrationTrait])),
        .product(name: "MembraneCore", package: "Membrane", condition: .when(traits: [integrationTrait])),
    ]
    swarmSwiftSettings.append(.define("SWARM_INTEGRATIONS", .when(traits: [integrationTrait])))
}

let swarmCoreOnlyExcludes = [
    "Integration/Wax",
    "Integration/Membrane/SessionMembraneAgentAdapter.swift",
    "Integration/Membrane/WaxMembraneStorage.swift",
    "Internal/GraphRuntime",
    "Memory/ContextCoreMemory.swift",
    "Memory/DefaultAgentMemory.swift",
    "Tools/Web",
    "Workflow/WorkflowCheckpointCodec.swift",
    "Workflow/WorkflowCheckpointStore.swift",
    "Workflow/WorkflowDurableEngine.swift",
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
        exclude: coreOnly ? swarmCoreOnlyExcludes : [],
        swiftSettings: swarmSwiftSettings
    ),
    .target(
        name: "SwarmOpenTelemetry",
        dependencies: [
            "Swarm",
            .product(name: "OpenTelemetryApi", package: "opentelemetry-swift-core"),
        ],
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
            var dependencies: [Target.Dependency] = [
                "Swarm",
                "SwarmMCP",
            ]
            if !coreOnly {
                dependencies += [
                    .product(name: "Membrane", package: "Membrane", condition: .when(traits: [integrationTrait])),
                    .product(name: "MembraneCore", package: "Membrane", condition: .when(traits: [integrationTrait])),
                ]
            }
            return dependencies
        }(),
        resources: [],
        swiftSettings: swarmSwiftSettings
    ),
    .testTarget(
        name: "SwarmMacrosTests",
        dependencies: [
            "Swarm",
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
        // Inherit SWARM_INTEGRATIONS so requiredFamilies/durable match the support target.
        swiftSettings: swarmSwiftSettings
    ),
    .testTarget(
        name: "SwarmOpenTelemetryTests",
        dependencies: [
            "Swarm",
            "SwarmOpenTelemetry",
            .product(name: "OpenTelemetrySdk", package: "opentelemetry-swift-core"),
        ],
        swiftSettings: swarmSwiftSettings
    )
]

if !coreOnly {
    packageTargets.append(
        .testTarget(
            name: "HiveSwarmTests",
            dependencies: [
                "Swarm",
                .product(name: "HiveCore", package: "Hive", condition: .when(traits: [integrationTrait])),
            ],
            swiftSettings: swarmSwiftSettings
        )
    )
}

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
        // Lean default: core Swarm + Foundation Models only. Opt in for full graph.
        .default(enabledTraits: []),
        .trait(
            name: integrationTrait,
            description: """
            Enable SWARM_INTEGRATIONS: durable Hive workflows, ContextCore+Wax default memory, \
            Membrane adapters, and web helpers. Off by default. Hive/Membrane/ContextCore are \
            planned as in-tree Sources/ targets; Wax remains an external package for now.
            """
        ),
    ],
    dependencies: packageDependencies,
    targets: packageTargets
)
