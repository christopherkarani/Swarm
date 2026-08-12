# Embedding Resources

[![Discord](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fdiscord.com%2Fapi%2Fv10%2Finvites%2FNHgNh7HJ6M%3Fwith_counts%3Dtrue&query=%24.approximate_presence_count&suffix=%20online&logo=discord&label=Discord&color=5865F2)](https://discord.gg/NHgNh7HJ6M)

The MiniLM package is **not** shipped with Swarm (download-on-demand, not a
43 MB bundle). Apps that self-bundle may still place `minilm-l6-v2.mlpackage`
here; `CoreMLEmbeddingProvider` checks the compiled Application Support cache
first, then this bundle path.

Without a cached or bundled model, the provider falls back to deterministic
pseudo-embeddings and logs a once-per-process warning. Call
`SemanticEmbeddingAvailability.ensureModelAvailable()` to download, verify,
and compile the model.
