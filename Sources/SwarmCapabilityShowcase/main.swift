import Foundation
import SwarmCapabilityShowcaseSupport

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@main
enum SwarmCapabilityShowcaseCLI {
    static func main() async {
        do {
            let exitCode = try await run(arguments: Array(CommandLine.arguments.dropFirst()))
            exit(exitCode)
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func run(arguments: [String]) async throws -> Int32 {
        let showcase = CapabilityShowcase()
        let command = arguments.first ?? "matrix"

        switch command {
        case "list":
            print(showcase.renderCatalog())
            return 0

        case "run":
            guard let id = arguments.dropFirst().first else {
                printUsage()
                return 1
            }
            let result = try await showcase.runScenario(id: id)
            print(CapabilityShowcase.renderSummary([result]))
            return result.status == .failed ? 1 : 0

        case "matrix":
            let results = try await showcase.runDeterministicScenarios()
            print(CapabilityShowcase.renderSummary(results))
            return results.contains(where: { $0.status == .failed }) ? 1 : 0

        case "smoke":
            let results = try await showcase.runSmokeScenarios()
            print(CapabilityShowcase.renderSummary(results))
            return results.contains(where: { $0.status == .failed }) ? 1 : 0

        default:
            printUsage()
            return 1
        }
    }

    private static func printUsage() {
        print(
            """
            Usage: swift run SwarmCapabilityShowcase [list|matrix|run <scenario-id>|smoke]

            list   Print the registered scenario catalog.
            matrix Run the deterministic capability matrix.
            run    Run a single scenario by id.
            smoke  Run opt-in smoke scenarios.
            """
        )
    }
}
