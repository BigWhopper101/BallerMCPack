#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:globals.glsl>

uniform sampler2D InSampler;
uniform sampler2D MainDepthSampler;

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 InSize;
    vec2 MainDepthSize;
};

layout(std140) uniform FxConfig {
    vec4 Params;  // x = focus depth, y = depth gain, z = max blur radius (px), w = reserved
};

layout(location = 0) in vec2 texCoord;

layout(location = 0) out vec4 fragColor;

// Depth-of-field: blur radius grows with |depth - focus|.
// Depth is raw (nonlinear) — Params.x/y tune the focus band in-game.
void main() {
    float depth = texture(MainDepthSampler, texCoord).x;
    float coc = clamp(abs(depth - Params.x) * Params.y, 0.0, Params.z);

    vec2 oneTexel = 1.0 / InSize;
    vec3 acc = texture(InSampler, texCoord).rgb;
    float wsum = 1.0;

    // 8-tap disc, radius scaled by circle of confusion
    vec2 taps[8];
    taps[0] = vec2( 1.0,  0.0); taps[1] = vec2( 0.7,  0.7);
    taps[2] = vec2( 0.0,  1.0); taps[3] = vec2(-0.7,  0.7);
    taps[4] = vec2(-1.0,  0.0); taps[5] = vec2(-0.7, -0.7);
    taps[6] = vec2( 0.0, -1.0); taps[7] = vec2( 0.7, -0.7);
    for (int i = 0; i < 8; i++) {
        acc += texture(InSampler, texCoord + taps[i] * coc * oneTexel).rgb;
        wsum += 1.0;
    }
    vec3 col = acc / wsum;

    // blurred areas lose a touch of contrast, like real optics
    float lum = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(col, vec3(lum), clamp(coc / max(Params.z, 0.001), 0.0, 1.0) * 0.15);

    fragColor = vec4(col, 1.0);
}
