import Compression
import Foundation

/// Minimal ZIP extractor for MiniLM release assets (stored + deflate).
enum EmbeddingModelZip {
    static func isZip(_ data: Data) -> Bool {
        guard data.count >= 4 else {
            return false
        }
        return data[0] == 0x50 && data[1] == 0x4B && (data[2] == 0x03 || data[2] == 0x05)
    }

    static func extract(archive data: Data, to destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let eocd = try findEndOfCentralDirectory(in: data)
        var offset = Int(eocd.centralDirectoryOffset)
        for _ in 0..<eocd.entryCount {
            guard offset + 46 <= data.count, data.u32(at: offset) == 0x0201_4B50 else {
                throw EmbeddingModelDeliveryError.compilationFailed("ZIP central directory is corrupt")
            }
            let method = data.u16(at: offset + 10)
            let compressedSize = Int(data.u32(at: offset + 20))
            let uncompressedSize = Int(data.u32(at: offset + 24))
            let nameLength = Int(data.u16(at: offset + 28))
            let extraLength = Int(data.u16(at: offset + 30))
            let commentLength = Int(data.u16(at: offset + 32))
            let localHeaderOffset = Int(data.u32(at: offset + 42))
            let nameStart = offset + 46
            guard nameStart + nameLength <= data.count else {
                throw EmbeddingModelDeliveryError.compilationFailed("ZIP entry name is truncated")
            }
            let name = String(
                data: data.subdata(in: nameStart..<(nameStart + nameLength)),
                encoding: .utf8
            ) ?? "entry"
            try extractEntry(
                data: data,
                localHeaderOffset: localHeaderOffset,
                method: method,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                relativePath: name,
                destination: destination
            )
            offset = nameStart + nameLength + extraLength + commentLength
        }
    }

    static func locateModelPackage(in directory: URL) throws -> URL {
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var packages: [URL] = []
        var models: [URL] = []
        while let item = enumerator?.nextObject() as? URL {
            if item.pathExtension == "mlpackage" {
                packages.append(item)
            } else if item.pathExtension == "mlmodel" {
                models.append(item)
            }
        }
        if let package = packages.first {
            return package
        }
        if let model = models.first {
            return model
        }
        throw EmbeddingModelDeliveryError.compilationFailed(
            "ZIP did not contain an .mlpackage or .mlmodel"
        )
    }

    private struct EndOfCentralDirectory {
        var entryCount: UInt16
        var centralDirectoryOffset: UInt32
    }

    private static func findEndOfCentralDirectory(in data: Data) throws -> EndOfCentralDirectory {
        let minimumEOCD = 22
        guard data.count >= minimumEOCD else {
            throw EmbeddingModelDeliveryError.compilationFailed("ZIP archive is too small")
        }
        let maxComment = 65_535
        let start = max(0, data.count - minimumEOCD - maxComment)
        var index = data.count - minimumEOCD
        while index >= start {
            if data.u32(at: index) == 0x0605_4B50 {
                return EndOfCentralDirectory(
                    entryCount: data.u16(at: index + 10),
                    centralDirectoryOffset: data.u32(at: index + 16)
                )
            }
            index -= 1
        }
        throw EmbeddingModelDeliveryError.compilationFailed("ZIP end-of-central-directory not found")
    }

    private static func extractEntry(
        data: Data,
        localHeaderOffset: Int,
        method: UInt16,
        compressedSize: Int,
        uncompressedSize: Int,
        relativePath: String,
        destination: URL
    ) throws {
        let output = try resolvedOutputURL(relativePath: relativePath, destination: destination)
        if relativePath.hasSuffix("/") || relativePath.isEmpty {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            return
        }

        guard localHeaderOffset + 30 <= data.count, data.u32(at: localHeaderOffset) == 0x0403_4B50 else {
            throw EmbeddingModelDeliveryError.compilationFailed("ZIP local header is corrupt")
        }
        let nameLength = Int(data.u16(at: localHeaderOffset + 26))
        let extraLength = Int(data.u16(at: localHeaderOffset + 28))
        let dataStart = localHeaderOffset + 30 + nameLength + extraLength
        let dataEnd = dataStart + compressedSize
        guard dataEnd <= data.count else {
            throw EmbeddingModelDeliveryError.compilationFailed("ZIP entry payload is truncated")
        }

        let payload = data.subdata(in: dataStart..<dataEnd)
        let inflated: Data
        switch method {
        case 0:
            inflated = payload
        case 8:
            inflated = try inflate(payload, uncompressedSize: uncompressedSize)
        default:
            throw EmbeddingModelDeliveryError.compilationFailed("Unsupported ZIP compression method \(method)")
        }

        try FileManager.default.createDirectory(
            at: output.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try inflated.write(to: output, options: .atomic)
    }

    /// Rejects absolute paths, `..` segments, and any resolved URL outside `destination`.
    private static func resolvedOutputURL(relativePath: String, destination: URL) throws -> URL {
        let normalized = relativePath.replacingOccurrences(of: "\\", with: "/")
        if normalized.contains("\0") || normalized.hasPrefix("/") {
            throw EmbeddingModelDeliveryError.compilationFailed("ZIP entry path is not safe: \(relativePath)")
        }
        let segments = normalized.split(separator: "/", omittingEmptySubsequences: true)
        if segments.contains("..") {
            throw EmbeddingModelDeliveryError.compilationFailed("ZIP entry path is not safe: \(relativePath)")
        }

        let destinationRoot = destination.standardizedFileURL
        let output = destinationRoot.appendingPathComponent(normalized).standardizedFileURL
        let rootPath = destinationRoot.path
        let outputPath = output.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard outputPath == rootPath || outputPath.hasPrefix(prefix) else {
            throw EmbeddingModelDeliveryError.compilationFailed("ZIP entry path is not safe: \(relativePath)")
        }
        return output
    }

    /// ZIP method 8 is raw DEFLATE (RFC 1951), not zlib-wrapped (RFC 1950).
    private static func inflate(_ input: Data, uncompressedSize: Int) throws -> Data {
        guard !input.isEmpty else {
            return Data()
        }

        let capacity = max(uncompressedSize, input.count, 1)
        if let decoded = decodeZlib(input, capacity: capacity) {
            return decoded
        }

        var wrapped = Data([0x78, 0x01])
        wrapped.append(input)
        if let decoded = decodeZlib(wrapped, capacity: capacity) {
            return decoded
        }

        throw EmbeddingModelDeliveryError.compilationFailed("ZIP deflate failed")
    }

    private static func decodeZlib(_ input: Data, capacity: Int) -> Data? {
        var destination = Data(count: capacity)
        let decodedCount = input.withUnsafeBytes { sourceBuffer in
            destination.withUnsafeMutableBytes { destinationBuffer in
                guard let source = sourceBuffer.bindMemory(to: UInt8.self).baseAddress,
                      let dest = destinationBuffer.bindMemory(to: UInt8.self).baseAddress
                else {
                    return 0
                }
                return compression_decode_buffer(
                    dest,
                    capacity,
                    source,
                    input.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard decodedCount > 0 else {
            return nil
        }
        destination.count = decodedCount
        return destination
    }
}

private extension Data {
    func u16(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func u32(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16
            | UInt32(self[offset + 3]) << 24
    }
}
