import Foundation
@testable import Swarm
import Testing

@Suite("StructuredOutputResult decoding")
struct StructuredOutputDecodingTests {
    @Test("decoded reads raw JSON as a Decodable type")
    func decodedRoundTrip() throws {
        struct Answer: Decodable, Equatable {
            let value: Int
        }

        let result = StructuredOutputResult(
            format: .jsonObject,
            rawJSON: #"{"value":7}"#,
            value: .dictionary(["value": .int(7)]),
            source: .promptFallback
        )
        #expect(try result.decoded(as: Answer.self) == Answer(value: 7))
    }
}
