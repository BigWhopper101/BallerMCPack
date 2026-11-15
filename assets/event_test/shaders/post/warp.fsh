#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:globals.glsl>

uniform sampler2D InSampler;

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 InSize;
};

layout(std140) uniform FxConfig {
    vec4 Params;  // x = strength, y = chroma split, z = pulse freq (cycles/day), w = base level
};

layout(location = 0) in vec2 texCoord;

layout(location = 0) out vec4 fragColor;

// Radial zoom blur ("warp speed") with pulsing intensity and edge chroma split.
void main() {
    float pulse = Params.w + (1.0 - Params.w) * (0.5 + 0.5 * sin(GameTime * 6.2831853 * Params.z));

    vec2 dir = texCoord - 0.5;
    float reach = 0.22 * Params.x * pulse;

    vec3 acc = vec3(0.0);
    for (int i = 0; i < 8; i++) {
        float w = float(i) / 7.0;
        acc += texture(InSampler, texCoord - dir * w * reach).rgb;
    }
    acc /= 8.0;

    // chromatic split grows toward the edges
    float cd = length(dir);
    float cs = Params.y * 0.012 * (0.25 + cd);
    acc.r = mix(acc.r, texture(InSampler, texCoord + dir * cs).r, 0.85);
    acc.b = mix(acc.b, texture(InSampler, texCoord - dir * cs).b, 0.85);

    // light gathers along the streak direction
    acc *= 1.0 + 0.18 * pulse * cd;

    fragColor = vec4(acc, 1.0);
}
