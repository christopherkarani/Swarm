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
}
