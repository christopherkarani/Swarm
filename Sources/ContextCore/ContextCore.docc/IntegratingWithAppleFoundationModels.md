# Integrating With Apple Foundation Models

You can inject any embedding backend by conforming to ``EmbeddingProvider``.

```swift
import ContextCore
import FoundationModels

struct AppleFoundationEmbeddingProvider: EmbeddingProvider {
    let dimension = 384

    func embed(_ text: String) async throws -> [Float] {
        // Replace with the current FoundationModels embedding API.
        // Keep output normalized and stable in `dimension`.
        fatalError("Implement with your FoundationModels SDK version")
    }

    func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        var vectors: [[Float]] = []
        vectors.reserveCapacity(texts.count)
        for text in texts {
            vectors.append(try await embed(text))
        }
        return vectors
    }
}

struct FoundationModelsTokenCounter: TokenCounter {
    func count(_ text: String) -> Int {
        // Replace with exact tokenizer counting for your model.
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).count
    }
}

var config = ContextConfiguration.default
config.embeddingProvider = AppleFoundationEmbeddingProvider()
config.tokenCounter = FoundationModelsTokenCounter()

let context = try AgentContext(configuration: config)
```

## Notes

- Ensure your embedding dimension matches stored chunk vectors.
- Prefer exact tokenizer integration when available; then `tokenBudgetSafetyMargin` can be reduced.
- Keep provider behavior deterministic for reproducible benchmarks and tests.
