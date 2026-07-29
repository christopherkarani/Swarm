import Foundation

public protocol PointerStore: Sendable {
    func store(payload: Data, dataType: MemoryPointer.DataType, summary: String) async throws -> MemoryPointer
    func resolve(pointerID: String) async throws -> Data
    func delete(pointerID: String) async
}
