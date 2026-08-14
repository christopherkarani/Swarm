import Foundation
@testable import Swarm
import Testing

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@Suite("TraceContextHeaders")
struct TraceContextHeadersTests {
    @Test("Formats a spec-valid W3C traceparent")
    func formatsValidTraceparent() throws {
        let headers = try #require(
            TraceContextHeaders(
                traceId: "4bf92f3577b34da6a3ce929d0e0e4736",
                spanId: "00f067aa0ba902b7",
                sampled: true
            )
        )

        #expect(headers.traceparent == "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01")
        #expect(TraceContextHeaders.isValidTraceparent(headers.traceparent))
        #expect(headers.httpHeaders["traceparent"] == headers.traceparent)
        #expect(headers.httpHeaders["tracestate"] == nil)
    }

    @Test("Includes tracestate when present")
    func includesTracestate() throws {
        let headers = try #require(
            TraceContextHeaders(
                traceId: "4bf92f3577b34da6a3ce929d0e0e4736",
                spanId: "00f067aa0ba902b7",
                sampled: false,
                tracestate: "rojo=00f067aa0ba902b7"
            )
        )

        #expect(headers.traceparent.hasSuffix("-00"))
        #expect(headers.httpHeaders["tracestate"] == "rojo=00f067aa0ba902b7")
    }

    @Test("Rejects malformed identifiers")
    func rejectsMalformedIdentifiers() {
        #expect(TraceContextHeaders(traceId: "abc", spanId: "00f067aa0ba902b7") == nil)
        #expect(TraceContextHeaders(traceparent: "not-a-traceparent") == nil)
        #expect(TraceContextHeaders.isValidTraceparent("00-zzzz-00f067aa0ba902b7-01") == false)
    }

    @Test("applyCurrent injects headers onto a URLRequest")
    func applyCurrentInjectsHeaders() async throws {
        let headers = try #require(
            TraceContextHeaders(
                traceId: "4bf92f3577b34da6a3ce929d0e0e4736",
                spanId: "00f067aa0ba902b7"
            )
        )

        let request = await TraceContextHeaders.withCurrent(headers) {
            var request = URLRequest(url: URL(string: "https://example.com/v1")!)
            TraceContextHeaders.applyCurrent(to: &request)
            return request
        }

        #expect(request.value(forHTTPHeaderField: "traceparent") == headers.traceparent)
    }
}
