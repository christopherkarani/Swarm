#include <metal_stdlib>
using namespace metal;

constant uint relevance_shared_query_capacity = 1024;

kernel void relevance_score(
    device const float* query        [[buffer(0)]],
    device const float* chunks       [[buffer(1)]],
    device const float* recencyWts   [[buffer(2)]],
    constant float2& weights         [[buffer(3)]],
    device float* scores             [[buffer(4)]],
    constant uint& dim               [[buffer(5)]],
    constant uint& n                 [[buffer(6)]],
    constant float& queryNorm        [[buffer(7)]],
    uint3 gid                        [[thread_position_in_grid]],
    uint3 tid                        [[thread_position_in_threadgroup]],
    uint3 threadsPerThreadgroup      [[threads_per_threadgroup]]
) {
    threadgroup float sharedQuery[relevance_shared_query_capacity];
    const bool useSharedQuery = dim <= relevance_shared_query_capacity;
    if (useSharedQuery) {
        const uint threadCount = max(1u, threadsPerThreadgroup.x);
        for (uint index = tid.x; index < dim; index += threadCount) {
            sharedQuery[index] = query[index];
        }
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    if (gid.x >= n) {
        return;
    }

    const uint base = gid.x * dim;

    float dotProduct = 0.0f;
    float chunkNormSq = 0.0f;
    uint index = 0;

    if (useSharedQuery) {
        for (; index + 3 < dim; index += 4) {
            const float4 q = float4(sharedQuery[index], sharedQuery[index + 1], sharedQuery[index + 2], sharedQuery[index + 3]);
            const float4 c = float4(chunks[base + index], chunks[base + index + 1], chunks[base + index + 2], chunks[base + index + 3]);
            dotProduct += dot(q, c);
            chunkNormSq += dot(c, c);
        }

        for (; index < dim; ++index) {
            const float q = sharedQuery[index];
            const float c = chunks[base + index];
            dotProduct += q * c;
            chunkNormSq += c * c;
        }
    } else {
        for (; index + 3 < dim; index += 4) {
            const float4 q = float4(query[index], query[index + 1], query[index + 2], query[index + 3]);
            const float4 c = float4(chunks[base + index], chunks[base + index + 1], chunks[base + index + 2], chunks[base + index + 3]);
            dotProduct += dot(q, c);
            chunkNormSq += dot(c, c);
        }

        for (; index < dim; ++index) {
            const float q = query[index];
            const float c = chunks[base + index];
            dotProduct += q * c;
            chunkNormSq += c * c;
        }
    }

    const float chunkNorm = sqrt(chunkNormSq);

    float cosine = 0.0f;
    const float denom = queryNorm * chunkNorm;
    if (denom > 0.0f) {
        cosine = dotProduct / denom;
    }

    scores[gid.x] = cosine * weights.x + recencyWts[gid.x] * weights.y;
}

kernel void topk_indices(
    device const float* scores   [[buffer(0)]],
    device uint* indices         [[buffer(1)]],
    constant uint& n             [[buffer(2)]],
    constant uint& k             [[buffer(3)]],
    uint gid                     [[thread_position_in_grid]]
) {
    if (gid != 0) {
        return;
    }

    if (n == 0 || k == 0) {
        return;
    }

    const uint outCount = min(n, k);

    for (uint rank = 0; rank < outCount; ++rank) {
        float bestScore = -INFINITY;
        uint bestIndex = 0;

        for (uint i = 0; i < n; ++i) {
            bool selected = false;
            for (uint prev = 0; prev < rank; ++prev) {
                if (indices[prev] == i) {
                    selected = true;
                    break;
                }
            }

            if (selected) {
                continue;
            }

            const float score = scores[i];
            if (score > bestScore) {
                bestScore = score;
                bestIndex = i;
            }
        }

        indices[rank] = bestIndex;
    }

    for (uint rank = outCount; rank < k; ++rank) {
        indices[rank] = 0;
    }
}
