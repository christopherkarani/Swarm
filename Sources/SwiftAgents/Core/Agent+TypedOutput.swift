// Agent+TypedOutput.swift
// SwiftAgents Framework
//
// Typed JSON output helpers for agents.

import Foundation

public extension Agent {
    /// Executes the agent and decodes a JSON response into a typed value.
    ///
    /// This method injects a strict JSON-only response instruction and attempts
    /// to decode the agent's output into the requested Decodable type.
    func run<T: Decodable>(
        _ input: String,
        session: (any Session)? = nil,
        hooks: (any RunHooks)? = nil,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AgentError.invalidInput(reason: "Input cannot be empty")
        }

        let jsonInstruction = """
        Respond ONLY with valid JSON. Do not include markdown, code fences, or additional text.
        """
        let augmentedInput = "\(input)\n\n\(jsonInstruction)"

        let result = try await run(augmentedInput, session: session, hooks: hooks)
        let jsonString = JSONOutputExtractor.extract(from: result.output)

        guard let data = jsonString.data(using: .utf8) else {
            throw AgentError.generationFailed(reason: "Failed to encode JSON output as UTF-8")
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw AgentError.generationFailed(
                reason: "Failed to decode JSON output: \(String(describing: error))"
            )
        }
    }
}

private enum JSONOutputExtractor {
    static func extract(from response: String) -> String {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let startIndex = trimmed.firstIndex(where: { $0 == "{" || $0 == "[" }) else {
            return trimmed
        }

        var stack: [Character] = []
        var inString = false
        var escapeNext = false

        for index in trimmed[startIndex...].indices {
            let char = trimmed[index]

            if inString {
                if escapeNext {
                    escapeNext = false
                    continue
                }
                if char == "\\" {
                    escapeNext = true
                    continue
                }
                if char == "\"" {
                    inString = false
                }
                continue
            }

            if char == "\"" {
                inString = true
                continue
            }

            if char == "{" || char == "[" {
                stack.append(char)
            } else if char == "}" || char == "]" {
                if let last = stack.last, matches(last, char) {
                    stack.removeLast()
                    if stack.isEmpty {
                        return String(trimmed[startIndex...index])
                    }
                }
            }
        }

        return trimmed
    }

    private static func matches(_ open: Character, _ close: Character) -> Bool {
        switch (open, close) {
        case ("{", "}"), ("[", "]"):
            return true
        default:
            return false
        }
    }
}
