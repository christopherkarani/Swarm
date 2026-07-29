public struct MemoryPointer: Sendable, Hashable, Codable {
    public enum DataType: String, Sendable, Codable, Hashable {
        case document
        case matrix
        case image
        case binary
        case code
    }

    public let id: String
    public let dataType: DataType
    public let byteSize: Int
    public let summary: String

    public init(id: String, dataType: DataType, byteSize: Int, summary: String) {
        self.id = id
        self.dataType = dataType
        self.byteSize = byteSize
        self.summary = summary
    }
}
