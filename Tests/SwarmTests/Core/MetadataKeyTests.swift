// MetadataKeyTests.swift
// SwarmTests
//
// Tests for MetadataKey typed metadata access across result and trace seams.

import Foundation
@testable import Swarm
import Testing

// MARK: - MetadataKeyTests

@Suite("MetadataKey Tests")
struct MetadataKeyTests {

    // MARK: - Round-Trip Tests

    @Test("string key round-trips through result metadata")
    func stringKeyRoundTrip() {
        var metadata: [String: SendableValue] = [:]
        metadata[.runtimeEngine] = "graph"

        #expect(metadata[.runtimeEngine] == "graph")
        #expect(metadata["runtime.engine"] == .string("graph"))
    }

    @Test("integer key round-trips through trace metadata")
    func integerKeyRoundTrip() {
        var metadata: [String: SendableValue] = [:]
        metadata[.inputTokens] = 11

        #expect(metadata[.inputTokens] == 11)
        #expect(metadata["input_tokens"] == .int(11))
    }

    @Test("double key round-trips through trace metadata")
    func doubleKeyRoundTrip() {
        var metadata: [String: SendableValue] = [:]
        metadata[.durationMs] = 12.5

        #expect(metadata[.durationMs] == 12.5)
        #expect(metadata["durationMs"] == .double(12.5))
    }

    @Test("bool key round-trips through result metadata")
    func boolKeyRoundTrip() {
        var metadata: [String: SendableValue] = [:]
        metadata[.fallbackUsed] = true

        #expect(metadata[.fallbackUsed] == true)
        #expect(metadata["workflow.fallback.used"] == .bool(true))
    }

    @Test("tool success writes a bool payload, not strings")
    func toolSuccessWritesBoolPayload() {
        var metadata: [String: SendableValue] = [:]
        metadata[.toolSuccess] = true
        #expect(metadata["success"] == .bool(true))

        metadata[.toolSuccess] = false
        #expect(metadata["success"] == .bool(false))
        #expect(metadata[.toolSuccess] == false)
    }

    @Test("stream event keys round-trip through string dictionaries")
    func streamEventKeysRoundTrip() {
        var payload: [String: String] = [:]
        payload[StreamEventMetadata.model] = "gpt-test"
        payload[StreamEventMetadata.text] = "chunk"
        payload[StreamEventMetadata.name] = "echo"
        payload[StreamEventMetadata.success] = "true"
        payload[StreamEventMetadata.toolCallID] = "call-1"
        payload[StreamEventMetadata.output] = "ok"

        #expect(payload[StreamEventMetadata.model] == "gpt-test")
        #expect(payload[StreamEventMetadata.text] == "chunk")
        #expect(payload[StreamEventMetadata.name] == "echo")
        #expect(payload[StreamEventMetadata.success] == "true")
        #expect(payload[StreamEventMetadata.toolCallID] == "call-1")
        #expect(payload[StreamEventMetadata.output] == "ok")

        // Raw-string reads observe the same entries.
        #expect(payload["model"] == "gpt-test")
        #expect(payload["toolCallID"] == "call-1")
    }

    // MARK: - Serialized Form Tests

    @Test("key constants keep their serialized names")
    func keyConstantsKeepSerializedNames() {
        #expect(MetadataKey<String>.runtimeEngine.name == "runtime.engine")
        #expect(MetadataKey<Bool>.fallbackUsed.name == "workflow.fallback.used")
        #expect(MetadataKey<String>.fallbackError.name == "workflow.fallback.error")
        #expect(MetadataKey<Int>.inputTokens.name == "input_tokens")
        #expect(MetadataKey<Int>.outputTokens.name == "output_tokens")
        #expect(MetadataKey<Int>.totalTokens.name == "total_tokens")
        #expect(MetadataKey<Int>.legacyTokenCount.name == "tokenCount")
        #expect(MetadataKey<Int>.stepNumber.name == "stepNumber")
        #expect(MetadataKey<Double>.durationMs.name == "durationMs")
        #expect(MetadataKey<Bool>.toolSuccess.name == "success")
        #expect(StreamEventMetadata.model.name == "model")
        #expect(StreamEventMetadata.text.name == "text")
        #expect(StreamEventMetadata.name.name == "name")
        #expect(StreamEventMetadata.success.name == "success")
        #expect(StreamEventMetadata.toolCallID.name == "toolCallID")
        #expect(StreamEventMetadata.output.name == "output")
    }

    @Test("typed write overwrites and nil assignment removes the entry")
    func typedWriteOverwritesAndNilRemoves() {
        var metadata: [String: SendableValue] = [:]
        metadata[.totalTokens] = 1
        metadata[.totalTokens] = 2
        #expect(metadata["total_tokens"] == .int(2))

        metadata[.totalTokens] = nil
        #expect(metadata["total_tokens"] == nil)
    }

    // MARK: - Legacy Raw-String Interop Tests

    @Test("legacy tokenCount raw-string read observes typed legacy write")
    func legacyRawStringReadObservesTypedWrite() {
        var metadata: [String: SendableValue] = [:]
        metadata[.legacyTokenCount] = 120

        #expect(metadata["tokenCount"]?.intValue == 120)
    }

    @Test("raw-string write observes typed read")
    func rawStringWriteObservesTypedRead() {
        var metadata: [String: SendableValue] = [
            "workflow.fallback.used": .bool(true),
            "stepNumber": .int(3)
        ]

        #expect(metadata[.fallbackUsed] == true)
        #expect(metadata[.stepNumber] == 3)
    }

    // MARK: - Payload Mismatch Tests

    @Test("typed read returns nil for absent or mismatched payloads")
    func typedReadReturnsNilForAbsentOrMismatchedPayloads() {
        var metadata: [String: SendableValue] = ["stepNumber": .string("three")]

        #expect(metadata[.inputTokens] == nil)
        #expect(metadata[.stepNumber] == nil)

        metadata["durationMs"] = .int(5)
        // Double reads accept integer payloads via SendableValue.doubleValue.
        #expect(metadata[.durationMs] == 5.0)
    }

    // MARK: - Hashable Tests

    @Test("keys with equal name and value type are equal")
    func keysWithEqualNameAndTypeAreEqual() {
        let constructed = MetadataKey<Int>("input_tokens")

        #expect(constructed == .inputTokens)
        #expect(constructed.hashValue == MetadataKey<Int>.inputTokens.hashValue)
        #expect(constructed != .outputTokens)
    }

    @Test("keys deduplicate inside sets")
    func keysDeduplicateInsideSets() {
        var seen = Set<MetadataKey<Int>>()
        seen.insert(.inputTokens)
        seen.insert(MetadataKey<Int>("input_tokens"))

        #expect(seen.count == 1)
    }
}

// MARK: - AgentResult Runtime Engine Access Tests

@Suite("AgentResult.runtimeEngine Typed Key Tests")
struct AgentResultRuntimeEngineTypedKeyTests {

    @Test("accessor reads a value written through the typed key")
    func accessorReadsTypedKeyWrite() {
        var metadata: [String: SendableValue] = [:]
        metadata[.runtimeEngine] = "graph"

        let result = AgentResult(output: "hi", metadata: metadata)

        #expect(result.runtimeEngine == "graph")
    }

    @Test("accessor keeps reading legacy raw-string writes")
    func accessorReadsLegacyRawWrite() {
        let result = AgentResult(
            output: "hi",
            metadata: ["runtime.engine": .string("native")]
        )

        #expect(result.runtimeEngine == "native")
    }
}
