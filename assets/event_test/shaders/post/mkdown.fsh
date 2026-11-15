#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:globals.glsl>
#include <event_test:marker.glsl>

uniform sampler2D InSampler;

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 InSize;
};

layout(std140) uniform FxConfig {
    vec4 Params;  // unused, keeps the pass shape identical to its siblings
};

layout(location = 0) in vec2 texCoord;

layout(location = 0) out vec4 fragColor;

// Marker search, stage 1: downsample the frame to a small square target,
// keeping the MAX marker score per cell. Runs before the flash is composited,
// so it only ever sees the marker itself.
void main() {
    vec2 cell = floor(texCoord * OutSize);
    vec2 scale = InSize / OutSize;              // source px per cell
    vec2 origin = cell * scale;

    float best = 0.0;
    for (int y = 0; y < 4; y++) {
        for (int x = 0; x < 4; x++) {
            vec2 px = origin + (vec2(float(x), float(y)) + 0.5) * (scale * 0.25);
            best = max(best, markerScore(texture(InSampler, px / InSize).rgb));
        }
    }
    fragColor = vec4(best, best, best, 1.0);
}
