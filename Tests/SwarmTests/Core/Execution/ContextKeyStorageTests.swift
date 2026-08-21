import Foundation
@testable import Swarm
import Testing

@Suite("ContextKey storage identity")
struct ContextKeyStorageTests {
    @Test("Same name with different Value types do not share a slot")
    func typedKeysWithSameNameDoNotCollide() async throws {
        let context = AgentContext(input: "typed-keys")
        try await context.setTyped(ContextKey<String>("user_id"), value: "abc")
        try await context.setTyped(ContextKey<Int>("user_id"), value: 42)

        let stringValue: String? = await context.getTyped(ContextKey<String>("user_id"))
        let intValue: Int? = await context.getTyped(ContextKey<Int>("user_id"))
        #expect(stringValue == "abc")
        #expect(intValue == 42)
    }

    @Test("setTyped throws when encoding fails")
    func setTypedThrowsOnEncodeFailure() async {
        let context = AgentContext(input: "encode-failure")
        await #expect(throws: SendableValue.ConversionError.self) {
            try await context.setTyped(ContextKey<ThrowingEncodable>("broken"), value: ThrowingEncodable())
        }
        let stored: ThrowingEncodable? = await context.getTyped(ContextKey<ThrowingEncodable>("broken"))
        #expect(stored == nil)
    }
}

private struct ThrowingEncodable: Encodable, Decodable, Sendable {
    func encode(to encoder: Encoder) throws {
        throw EncodingError.invalidValue(
            self,
            EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "cannot encode")
        )
    }
}
