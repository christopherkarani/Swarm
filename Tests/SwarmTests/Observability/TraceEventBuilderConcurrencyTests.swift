// TraceEventBuilderConcurrencyTests.swift
// Swarm Framework
//
// TraceEvent.Builder is Sendable; concurrent use must not lose or corrupt state.

import Foundation
@testable import Swarm
import Testing

@Suite("TraceEvent.Builder Concurrency Tests")
struct TraceEventBuilderConcurrencyTests {
    @Test("Concurrent metadata writes from many tasks are all retained")
    func concurrentMetadataWritesAreRetained() async {
        let builder = TraceEvent.Builder(traceId: UUID(), kind: .custom, message: "shared")
        let tasks = 32
        let writesPerTask = 200

        await withTaskGroup(of: Void.self) { group in
            for task in 0 ..< tasks {
                group.addTask {
                    for write in 0 ..< writesPerTask {
                        builder.metadata(key: "k\(task)-\(write)", value: .int(write))
                        builder.message("task \(task)")
                    }
                }
            }
        }

        let event = builder.build()
        #expect(event.metadata.count == tasks * writesPerTask)
        #expect(event.message.hasPrefix("task "))
    }

    @Test("Builds race safely with setters")
    func buildsRaceSafelyWithSetters() async {
        let builder = TraceEvent.Builder(traceId: UUID(), kind: .custom, message: "racing")

        await withTaskGroup(of: Int.self) { group in
            for index in 0 ..< 64 {
                group.addTask {
                    builder.addingMetadata(["i\(index)": .int(index)])
                    return builder.build().metadata.count
                }
            }
            for await count in group {
                #expect(count >= 1)
            }
        }

        #expect(builder.build().metadata.count == 64)
    }
}
