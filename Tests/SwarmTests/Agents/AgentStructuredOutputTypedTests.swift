import Foundation
@testable import Swarm
import Testing

@Suite("Agent typed structured output", .ephemeralDefaultStores)
struct AgentStructuredOutputTypedTests {
    private struct Answer: Decodable, Sendable, Equatable {
        var value: Int
    }

    private struct Marker: Error, Equatable {}

    @Test("Generic runStructured decodes Output from valid JSON (AC-004)")
    func genericRunStructuredDecodesOutput() async throws {
        let provider = MockInferenceProvider(responses: [#"{"value":42}"#])
        let agent = try Agent(
            instructions: "Return structured JSON.",
            inferenceProvider: provider
        )

        let decoded = try await agent.runStructured(
            Answer.self,
            "Q",
            request: StructuredOutputRequest(format: .jsonObject)
        )

        #expect(decoded.output.value == 42)
        #expect(decoded.structuredOutput.rawJSON == #"{"value":42}"#)
        #expect(decoded.agentResult.output == #"{"value":42}"#)
    }

    @Test("Invalid JSON for Output throws structuredOutputDecodingFailed (AC-004)")
    func invalidJSONForTypeThrowsStructuredOutputDecodingFailed() async throws {
        let provider = MockInferenceProvider(responses: [#"{"other":true}"#])
        let agent = try Agent(
            instructions: "Return structured JSON.",
            inferenceProvider: provider
        )

        do {
            _ = try await agent.runStructured(
                Answer.self,
                "Q",
                request: StructuredOutputRequest(format: .jsonObject)
            )
            Issue.record("Expected structuredOutputDecodingFailed")
        } catch let error as AgentError {
            guard case let .structuredOutputDecodingFailed(reason, underlying) = error else {
                Issue.record("Wrong AgentError: \(error)")
                return
            }
            #expect(reason.isEmpty == false)
            #expect(underlying != nil)
            #expect(error.isRetryable == false)
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test("required false parse failure returns null value and assistant text (REQ-009)")
    func requiredFalseParseFailureDoesNotThrowOnNonGenericPath() async throws {
        let assistantText = "The answer is forty-two."
        let provider = MockInferenceProvider(responses: [assistantText])
        let agent = try Agent(
            instructions: "Return structured JSON.",
            inferenceProvider: provider
        )

        let result = try await agent.runStructured(
            "Q",
            request: StructuredOutputRequest(format: .jsonObject, required: false)
        )

        #expect(result.structuredOutput.value == .null)
        #expect(result.structuredOutput.rawJSON == assistantText)
        #expect(result.agentResult.output == assistantText)
    }

    @Test("Generic runStructured still throws when required is false and JSON does not decode")
    func genericRunStructuredThrowsOnDecodeFailureWhenRequiredIsFalse() async throws {
        let provider = MockInferenceProvider(responses: ["not a json object"])
        let agent = try Agent(
            instructions: "Return structured JSON.",
            inferenceProvider: provider
        )

        do {
            _ = try await agent.runStructured(
                Answer.self,
                "Q",
                request: StructuredOutputRequest(format: .jsonObject, required: false)
            )
            Issue.record("Expected structuredOutputDecodingFailed")
        } catch let error as AgentError {
            guard case .structuredOutputDecodingFailed = error else {
                Issue.record("Wrong AgentError: \(error)")
                return
            }
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test("required true keeps throw-on-parse-failure")
    func requiredTrueParseFailureStillThrows() async throws {
        let provider = MockInferenceProvider(responses: ["not a json object"])
        let agent = try Agent(
            instructions: "Return structured JSON.",
            inferenceProvider: provider
        )

        do {
            _ = try await agent.runStructured(
                "Q",
                request: StructuredOutputRequest(format: .jsonObject, required: true)
            )
            Issue.record("Expected generationFailed")
        } catch let error as AgentError {
            guard case .generationFailed = error else {
                Issue.record("Wrong AgentError: \(error)")
                return
            }
        } catch {
            Issue.record("Wrong error type: \(error)")
        }
    }

    @Test("structuredOutputDecodingFailed equality compares underlying like toolFailure")
    func structuredOutputDecodingFailedEqualityMatchesToolFailureCause() {
        let marker = Marker()
        let left = AgentError.structuredOutputDecodingFailed(reason: "bad json", underlying: marker)
        let right = AgentError.structuredOutputDecodingFailed(reason: "bad json", underlying: Marker())
        let differentReason = AgentError.structuredOutputDecodingFailed(reason: "other", underlying: marker)
        let missingCause = AgentError.structuredOutputDecodingFailed(reason: "bad json", underlying: nil)

        #expect(left == right)
        #expect(left != differentReason)
        #expect(left != missingCause)
        #expect(left.errorDescription?.contains("bad json") == true)
        #expect(left.isRetryable == false)
    }
}
