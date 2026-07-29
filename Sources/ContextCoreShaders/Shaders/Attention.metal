#include <metal_stdlib>
using namespace metal;

kernel void token_centrality(
    device const float* embeddings   [[buffer(0)]],
    device float* centrality         [[buffer(1)]],
    constant uint& dim               [[buffer(2)]],
    constant uint& n                 [[buffer(3)]],
    uint gid                         [[thread_position_in_grid]],
    uint tid                         [[thread_index_in_threadgroup]]
) {
    threadgroup float shared_data[1];
    if (tid == 0) {
        shared_data[0] = 0.0f;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    if (gid >= n) {
        return;
    }

    if (n <= 1) {
        centrality[gid] = 0.0f;
        return;
    }

    const uint base = gid * dim;

    float normSelfSq = 0.0f;
    for (uint d = 0; d < dim; ++d) {
        const float v = embeddings[base + d];
        normSelfSq += v * v;
    }
    const float normSelf = sqrt(normSelfSq);

    float sum = 0.0f;

    for (uint j = 0; j < n; ++j) {
        if (j == gid) {
            continue;
        }

        const uint otherBase = j * dim;
        float dot = 0.0f;
        float normOtherSq = 0.0f;

        for (uint d = 0; d < dim; ++d) {
            const float self = embeddings[base + d];
            const float other = embeddings[otherBase + d];
            dot += self * other;
            normOtherSq += other * other;
        }

        const float denom = normSelf * sqrt(normOtherSq);
        if (denom > 0.0f) {
            sum += dot / denom;
        }
    }

    centrality[gid] = sum / float(n - 1);
}

kernel void cross_attention_score(
    device const float* taskQuery      [[buffer(0)]],
    device const float* embeddings     [[buffer(1)]],
    device const float* centrality     [[buffer(2)]],
    device const float2* weights       [[buffer(3)]],
    device float* evictionScores       [[buffer(4)]],
    constant uint& dim                 [[buffer(5)]],
    constant uint& n                   [[buffer(6)]],
    uint gid                           [[thread_position_in_grid]]
) {
    if (gid >= n) {
        return;
    }

    const uint base = gid * dim;

    float dot = 0.0f;
    float queryNormSq = 0.0f;
    float chunkNormSq = 0.0f;

    for (uint d = 0; d < dim; ++d) {
        const float q = taskQuery[d];
        const float c = embeddings[base + d];
        dot += q * c;
        queryNormSq += q * q;
        chunkNormSq += c * c;
    }

    const float denom = sqrt(queryNormSq) * sqrt(chunkNormSq);
    float relevance = 0.0f;
    if (denom > 0.0f) {
        relevance = dot / denom;
    }

    evictionScores[gid] = relevance * weights[0].x + centrality[gid] * weights[0].y;
}
