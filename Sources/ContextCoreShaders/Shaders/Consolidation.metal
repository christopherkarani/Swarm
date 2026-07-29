#include <metal_stdlib>
using namespace metal;

kernel void pairwise_similarity(
    device const float* embeddings         [[buffer(0)]],
    device float* similarity               [[buffer(1)]],
    constant uint& dim                     [[buffer(2)]],
    constant uint& n                       [[buffer(3)]],
    uint2 gid                              [[thread_position_in_grid]]
) {
    const uint i = gid.x;
    const uint j = gid.y;

    if (i >= n || j >= n || j <= i) {
        return;
    }

    const uint baseI = i * dim;
    const uint baseJ = j * dim;

    float dot = 0.0f;
    float normISq = 0.0f;
    float normJSq = 0.0f;

    for (uint d = 0; d < dim; ++d) {
        const float a = embeddings[baseI + d];
        const float b = embeddings[baseJ + d];
        dot += a * b;
        normISq += a * a;
        normJSq += b * b;
    }

    float cosine = 0.0f;
    const float denom = sqrt(normISq) * sqrt(normJSq);
    if (denom > 0.0f) {
        cosine = dot / denom;
    }

    similarity[i * n + j] = cosine;
}

kernel void find_merge_candidates(
    device const float* similarity         [[buffer(0)]],
    device uint2* candidates               [[buffer(1)]],
    device atomic_uint* candidateCount     [[buffer(2)]],
    constant float& threshold              [[buffer(3)]],
    constant uint& n                       [[buffer(4)]],
    constant uint& maxCandidates           [[buffer(5)]],
    uint2 gid                              [[thread_position_in_grid]]
) {
    const uint i = gid.x;
    const uint j = gid.y;

    if (i >= n || j >= n || j <= i) {
        return;
    }

    const float value = similarity[i * n + j];
    if (value <= threshold) {
        return;
    }

    const uint idx = atomic_fetch_add_explicit(candidateCount, 1u, memory_order_relaxed);
    if (idx < maxCandidates) {
        candidates[idx] = uint2(i, j);
    }
}

kernel void pairwise_similarity_tiled(
    device const float* embeddings         [[buffer(0)]],
    device float* similarityTile           [[buffer(1)]],
    constant uint& dim                     [[buffer(2)]],
    constant uint& n                       [[buffer(3)]],
    constant uint& rowOffset               [[buffer(4)]],
    constant uint& colOffset               [[buffer(5)]],
    constant uint& rowCount                [[buffer(6)]],
    constant uint& colCount                [[buffer(7)]],
    uint2 gid                              [[thread_position_in_grid]]
) {
    const uint localI = gid.x;
    const uint localJ = gid.y;
    if (localI >= rowCount || localJ >= colCount) {
        return;
    }

    const uint i = rowOffset + localI;
    const uint j = colOffset + localJ;
    if (i >= n || j >= n || j <= i) {
        return;
    }

    const uint baseI = i * dim;
    const uint baseJ = j * dim;

    float dot = 0.0f;
    float normISq = 0.0f;
    float normJSq = 0.0f;

    for (uint d = 0; d < dim; ++d) {
        const float a = embeddings[baseI + d];
        const float b = embeddings[baseJ + d];
        dot += a * b;
        normISq += a * a;
        normJSq += b * b;
    }

    float cosine = 0.0f;
    const float denom = sqrt(normISq) * sqrt(normJSq);
    if (denom > 0.0f) {
        cosine = dot / denom;
    }

    similarityTile[localI * colCount + localJ] = cosine;
}

kernel void antipodal_test(
    device const float* embeddingsA         [[buffer(0)]],
    device const float* embeddingsB         [[buffer(1)]],
    device float* antipodalFraction         [[buffer(2)]],
    constant uint& dim                      [[buffer(3)]],
    constant uint& pairCount                [[buffer(4)]],
    uint gid                                [[thread_position_in_grid]]
) {
    if (gid >= pairCount) {
        return;
    }

    const uint base = gid * dim;
    uint signDiffCount = 0;

    for (uint d = 0; d < dim; ++d) {
        const bool signA = embeddingsA[base + d] >= 0.0f;
        const bool signB = embeddingsB[base + d] >= 0.0f;
        if (signA != signB) {
            signDiffCount += 1;
        }
    }

    antipodalFraction[gid] = float(signDiffCount) / float(dim);
}
