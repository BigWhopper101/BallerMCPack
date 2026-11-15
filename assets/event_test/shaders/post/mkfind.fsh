#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:globals.glsl>
#include <event_test:bus.glsl>

uniform sampler2D InSampler;
uniform sampler2D In2Sampler;

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 InSize;
    vec2 In2Size;
};

layout(location = 0) in vec2 texCoord;

layout(location = 0) out vec4 fragColor;

// Marker search, stage 2. The output target is 1x1, so the whole scan runs on
// a single pixel and is essentially free. Writes the argmax cell (rg) and its
// score (b); the consumer refines the position to sub-cell accuracy.
//
// With the bus live the scan is limited to a window around the bus-projected
// anchor: that projection is accurate to a couple of percent, so the real
// marker is always inside the window, and a magenta-ish block anywhere else on
// screen can never win the argmax.
//
// Loop bounds come from the size uniform on purpose: constant bounds let the
// driver try to unroll tens of thousands of iterations.
void main() {
    int w = int(InSize.x);
    int h = int(InSize.y);

    bool windowed = busSync(In2Sampler) > 0.5;
    ivec2 centre = ivec2(vec2(busChannel10(In2Sampler, BUS_U),
                             busChannel10(In2Sampler, BUS_V)) * InSize);
    int R = 56;                       // +-56 of 256 cells ~ +-22% of the screen

    ivec2 lo = windowed ? max(centre - ivec2(R), ivec2(0)) : ivec2(0);
    ivec2 hi = windowed ? min(centre + ivec2(R), ivec2(w - 1, h - 1)) : ivec2(w - 1, h - 1);

    float best = 0.0;
    vec2 bestUV = vec2(0.5);
    for (int y = 0; y < h; y++) {
        if (y < lo.y || y > hi.y) continue;
        for (int x = 0; x < w; x++) {
            if (x < lo.x || x > hi.x) continue;
            float k = texelFetch(InSampler, ivec2(x, y), 0).r;
            if (k > best) {
                best = k;
                bestUV = (vec2(float(x), float(y)) + 0.5) / vec2(float(w), float(h));
            }
        }
    }
    fragColor = vec4(bestUV, best, 1.0);
}
