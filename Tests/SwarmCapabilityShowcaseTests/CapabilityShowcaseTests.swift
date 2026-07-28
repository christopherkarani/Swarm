import Foundation
import Testing
@testable import SwarmCapabilityShowcaseSupport

@Suite("Swarm Capability Showcase", .serialized)
struct CapabilityShowcaseTests {
    @Test("registry covers every required capability family")
    func registryCoversRequiredFamilies() {
        let showcase = CapabilityShowcase()
        let coveredFamilies = Set(showcase.scenarios.flatMap(\.families))

        #expect(coveredFamilies == CapabilityShowcase.requiredFamilies)
    }

    @Test("deterministic scenarios pass")
    func deterministicScenariosPass() async throws {
        let showcase = CapabilityShowcase()
        let results = try await showcase.runDeterministicScenarios()

        #expect(results.isEmpty == false)
        if !results.allSatisfy({ $0.status == .passed }) {
            Issue.record("Capability showcase summary:\n\(CapabilityShowcase.renderSummary(results))")
        }
        #expect(results.allSatisfy { $0.status == .passed })

        // Strengthened assertions: verify externally-visible side effects rather
        // than trusting the showcase's self-reported status flag. Each scenario
        // must produce a non-empty summary describing what it exercised, and
        // every required capability family must be covered by at least one
        // passing scenario. Without these, a regression that broke a capability
        // could still report "passed" if the showcase's status accounting drifted.
        for result in results {
            #expect(!result.id.isEmpty, "scenario id should not be empty")
            #expect(!result.name.isEmpty, "scenario \(result.id) name should not be empty")
            #expect(!result.summary.isEmpty, "scenario \(result.id) summary should not be empty")
            #expect(!result.families.isEmpty, "scenario \(result.id) should declare at least one capability family")
        }

        let passedFamilies = Set(
            results
                .filter { $0.status == .passed }
                .flatMap(\.families)
        )
        for family in CapabilityShowcase.requiredFamilies {
            #expect(
                passedFamilies.contains(family),
                "required capability family \(family) is not covered by any passing scenario"
            )
        }
    }

    @Test("summary formatter includes ids and statuses")
    func summaryFormatterIncludesIdsAndStatuses() {
        let summary = CapabilityShowcase.renderSummary([
            CapabilityScenarioResult(
                id: "agent-tools",
                name: "Agent Tools",
                families: [.agentTools],
                status: .passed,
                summary: "ok"
            ),
            CapabilityScenarioResult(
                id: "mcp",
                name: "MCP",
                families: [.mcp],
                status: .skipped,
                summary: "missing env"
            ),
        ])

        #expect(summary.contains("agent-tools"))
        #expect(summary.contains("mcp"))
        #expect(summary.contains("passed"))
        #expect(summary.contains("skipped"))
    }

    @Test("guide scenario tables match registry")
    func guideScenarioTablesMatchRegistry() throws {
        let guide = try String(contentsOf: repoRoot.appendingPathComponent("docs/guide/capability-showcase.md"), encoding: .utf8)
        let showcase = CapabilityShowcase()

        let deterministicIDs = Set(showcase.scenarios.filter { $0.kind == .deterministic }.map(\.id))
        let smokeIDs = Set(showcase.scenarios.filter { $0.kind == .smoke }.map(\.id))

        for id in deterministicIDs.union(smokeIDs) {
            #expect(guide.contains("| `\(id)` |"), "capability showcase guide should document scenario \(id)")
        }

        let documentedIDs = Set(
            guide
                .split(separator: "\n")
                .compactMap { line -> String? in
                    guard line.hasPrefix("| `") else { return nil }
                    let parts = line.split(separator: "`")
                    guard parts.count >= 2 else { return nil }
                    return String(parts[1])
                }
        )

        let registryIDs = deterministicIDs.union(smokeIDs)
        // Guide always documents durable; the lean default registry omits it when
        // Integrations is off. Compare against the runtime registry, not #if.
        #expect(documentedIDs.isSuperset(of: registryIDs))
        let guideOnly = documentedIDs.subtracting(registryIDs)
        #expect(guideOnly.isSubset(of: ["durable"]))
    }

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
