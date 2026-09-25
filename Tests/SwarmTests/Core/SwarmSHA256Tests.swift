import Foundation
@testable import Swarm
import Testing

@Suite("SwarmSHA256")
struct SwarmSHA256Tests {
    @Test("hashes NIST empty-message vector")
    func emptyMessageVector() {
        #expect(
            SwarmSHA256.hex(Data())
                == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }

    @Test("hashes NIST abc vector")
    func abcVector() {
        #expect(
            SwarmSHA256.hex(Data("abc".utf8))
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    @Test("transcriptHash uses the portable digest")
    func transcriptHashUsesPortableDigest() throws {
        let transcript = SwarmTranscript(memoryMessages: [
            MemoryMessage(role: .user, content: "hello"),
        ])
        let data = try transcript.stableData()
        #expect(try transcript.transcriptHash() == SwarmSHA256.hex(data))
    }

    @Test("hashes NIST multi-block vectors")
    func multiBlockVectors() {
        #expect(
            SwarmSHA256.hex(Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8))
                == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
        )
        #expect(
            SwarmSHA256.hex(Data(repeating: 0x61, count: 1000))
                == "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3"
        )
    }

    @Test("chunked updates match one-shot hashing")
    func chunkedUpdatesMatchOneShot() {
        let input = Data("The quick brown fox jumps over the lazy dog".utf8)
        let expected = SwarmSHA256.hex(input)

        var chunked = SwarmSHA256.Hasher()
        chunked.update(Data(input.prefix(10)))
        chunked.update(Data(input.suffix(from: 10)))
        #expect(chunked.finalize().map { String(format: "%02x", $0) }.joined() == expected)

        var bytewise = SwarmSHA256.Hasher()
        for byte in input {
            bytewise.update(Data([byte]))
        }
        #expect(bytewise.finalize().map { String(format: "%02x", $0) }.joined() == expected)
    }
}
