#include <metal_stdlib>
using namespace metal;

kernel void compute_recency_weights(
    device const float* timestamps     [[buffer(0)]],
    device float* weights              [[buffer(1)]],
    constant float& currentTime        [[buffer(2)]],
    constant float& halfLifeSeconds    [[buffer(3)]],
    constant uint& n                   [[buffer(4)]],
    uint gid                           [[thread_position_in_grid]]
) {
    if (gid >= n) {
        return;
    }

    const float age = currentTime - timestamps[gid];
    float value = exp(-0.693147f * age / halfLifeSeconds);
    value = clamp(value, 0.0f, 1.0f);
    weights[gid] = value;
}
