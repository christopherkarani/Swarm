#include <metal_stdlib>
using namespace metal;

kernel void sentence_importance(
    device const float* sentenceEmbs  [[buffer(0)]],
    device const float* chunkQuery    [[buffer(1)]],
    device float* importance          [[buffer(2)]],
    constant uint& dim                [[buffer(3)]],
    constant uint& m                  [[buffer(4)]],
    uint gid                          [[thread_position_in_grid]]
) {
    if (gid >= m) {
        return;
    }

    const uint base = gid * dim;

    float dot = 0.0f;
    float sentenceNormSq = 0.0f;
    float queryNormSq = 0.0f;

    for (uint d = 0; d < dim; ++d) {
        const float s = sentenceEmbs[base + d];
        const float q = chunkQuery[d];
        dot += s * q;
        sentenceNormSq += s * s;
        queryNormSq += q * q;
    }

    const float denom = sqrt(sentenceNormSq) * sqrt(queryNormSq);
    float cosine = 0.0f;
    if (denom > 0.0f) {
        cosine = dot / denom;
    }

    importance[gid] = cosine;
}
