#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:globals.glsl>

uniform sampler2D InSampler;
uniform sampler2D PrevSampler;

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 InSize;
    vec2 PrevSize;
};

layout(std140) uniform FxConfig {
    vec4 Params;  // x = decay, y = glow amount, z/w reserved
};

layout(location = 0) in vec2 texCoord;

layout(location = 0) out vec4 fragColor;

// Persistent-buffer feedback: bright motion leaves fading ghosts.
// PrevSampler reads the persistent "hist" target (last frame's result).
void main() {
    vec3 now = texture(InSampler, texCoord).rgb;
    vec3 prev = texture(PrevSampler, texCoord).rgb * Params.x;

    vec3 col = max(now, prev);

    // ghost glow: old light bleeds a touch brighter than pure decay
    col += prev * Params.y * (1.0 - step(0.001, dot(abs(now - prev), vec3(1.0))));

    fragColor = vec4(col, 1.0);
}
