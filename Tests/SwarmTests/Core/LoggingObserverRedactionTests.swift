import Foundation
@testable import Swarm
import Testing

@Suite("LoggingObserver content redaction")
struct LoggingObserverRedactionTests {
    @Test("Content is redacted by default")
    func contentRedactedByDefault() {
        let observer = LoggingObserver()
        #expect(observer.logsContent == false)

        let description = observer.contentDescription("my password is hunter2")
        #expect(!description.contains("hunter2"))
        #expect(description == "<redacted, 22 chars>")
    }

    @Test("Opting in logs truncated content")
    func optInLogsTruncatedContent() {
        let observer = LoggingObserver(logsContent: true)
        #expect(observer.contentDescription("hello") == "\"hello\"")

        let long = String(repeating: "a", count: 150)
        #expect(observer.contentDescription(long) == "\"" + String(repeating: "a", count: 100) + "...\"")
    }
}
