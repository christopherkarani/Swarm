import ContextCoreShaders
import ContextCoreTypes
import Foundation
import Metal

enum MetalContext {
    static func device() throws -> MTLDevice {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ContextCoreError.metalDeviceUnavailable
        }
        return device
    }

    static func commandQueue(device: MTLDevice) throws -> MTLCommandQueue {
        guard let queue = device.makeCommandQueue() else {
            throw ContextCoreError.compressionFailed("Failed to create Metal command queue")
        }
        return queue
    }

    static func library(device: MTLDevice) throws -> MTLLibrary {
        let bundle = ContextCoreShadersModule.bundle

        if let defaultLibrary = try? device.makeDefaultLibrary(bundle: bundle) {
            return defaultLibrary
        }

        let shaderNames = ["Relevance", "Recency", "Attention", "Compression", "Consolidation"]
        let source = try shaderNames.map { name -> String in
            let url = bundle.url(forResource: name, withExtension: "metal")
                ?? bundle.url(forResource: name, withExtension: "metal", subdirectory: "Shaders")

            guard let url else {
                throw ContextCoreError.compressionFailed("Missing shader resource: \(name).metal")
            }
            return try String(contentsOf: url)
        }.joined(separator: "\n\n")

        let options = MTLCompileOptions()
        options.fastMathEnabled = false

        do {
            return try device.makeLibrary(source: source, options: options)
        } catch {
            throw ContextCoreError.compressionFailed("Failed to compile Metal shader sources: \(error)")
        }
    }

    static func awaitCompletion(of commandBuffer: MTLCommandBuffer) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            commandBuffer.addCompletedHandler { buffer in
                if let error = buffer.error {
                    continuation.resume(throwing: ContextCoreError.compressionFailed("Metal command failed: \(error.localizedDescription)"))
                    return
                }
                continuation.resume(returning: ())
            }
            commandBuffer.commit()
        }
    }

    static func threadsPerThreadgroup(
        pipeline: MTLComputePipelineState,
        count: Int
    ) -> MTLSize {
        let width = max(1, min(pipeline.maxTotalThreadsPerThreadgroup, count))
        return MTLSize(width: width, height: 1, depth: 1)
    }

    static func threadgroups(
        threadsPerThreadgroup: MTLSize,
        count: Int
    ) -> MTLSize {
        let groups = (count + threadsPerThreadgroup.width - 1) / threadsPerThreadgroup.width
        return MTLSize(width: max(1, groups), height: 1, depth: 1)
    }
}

extension MTLDevice {
    func makeBuffer(from array: [Float]) -> MTLBuffer? {
        array.withUnsafeBufferPointer { pointer in
            guard let baseAddress = pointer.baseAddress else {
                return nil
            }
            return makeBuffer(
                bytes: baseAddress,
                length: pointer.count * MemoryLayout<Float>.stride,
                options: .storageModeShared
            )
        }
    }

    func makeBuffer(from array: [UInt32]) -> MTLBuffer? {
        array.withUnsafeBufferPointer { pointer in
            guard let baseAddress = pointer.baseAddress else {
                return nil
            }
            return makeBuffer(
                bytes: baseAddress,
                length: pointer.count * MemoryLayout<UInt32>.stride,
                options: .storageModeShared
            )
        }
    }
}
