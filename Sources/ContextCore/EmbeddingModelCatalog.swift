import Foundation

/// Published MiniLM asset coordinates for download-on-demand delivery.
///
/// The compiled model is **not** bundled with Swarm (a ~43 MB `.mlpackage`
/// would dominate the package). Call
/// ``SemanticEmbeddingAvailability/ensureModelAvailable(configuration:progressHandler:)``
/// to download, verify, and compile it into Application Support.
///
/// ## Publishing target
///
/// At release time, attach `minilm-l6-v2.mlpackage.zip` to a GitHub release
/// whose tag matches ``releaseTag`` on `https://github.com/christopherkarani/Swarm`,
/// then replace ``expectedSHA256`` with the SHA-256 of that zip. See
/// `docs/release/release-checklist.md`.
public enum EmbeddingModelCatalog: Sendable {
    /// GitHub release tag that hosts the MiniLM asset.
    ///
    /// Publishing target — create this release (or attach the asset to the
    /// current Swarm tag) when cutting a release that should serve embeddings.
    public static let releaseTag = "embedding-minilm-l6-v2"

    /// File name of the GitHub release asset (zip of the `.mlpackage`).
    public static let assetFileName = "minilm-l6-v2.mlpackage.zip"

    /// Default download URL. **Publishing target** — 404 until the asset is attached.
    public static let defaultSourceURL = URL(
        string: "https://github.com/christopherkarani/Swarm/releases/download/\(releaseTag)/\(assetFileName)"
    )!

    /// Pinned SHA-256 of the published release asset bytes (lowercase hex).
    ///
    /// Placeholder until the first asset is published. `ensureModelAvailable()`
    /// will reject any download that does not match this digest. Update this
    /// constant in the same release that attaches the asset.
    public static let expectedSHA256 =
        "0000000000000000000000000000000000000000000000000000000000000000"

    /// Compiled model directory name stored under the cache root.
    public static let compiledModelDirectoryName = "minilm-l6-v2.mlmodelc"

    /// Sidecar file recording the SHA-256 of the asset that produced the cache.
    public static let hashSidecarFileName = "minilm-l6-v2.sha256"

    /// Default compiled-model cache: `~/Library/Application Support/Swarm/Embeddings/`.
    public static var defaultCacheDirectory: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent("Swarm/Embeddings", isDirectory: true)
    }
}
