#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:globals.glsl>
#include <event_test:grade.glsl>

layout(std140) uniform FxConfig {
    vec4 Params;  // x = overall mix with the untouched frame, y = ramp strength x, z = unused, w = glow x
};

layout(location = 0) in vec2 texCoord;
layout(location = 0) out vec4 fragColor;

// x_combo: double-exposure ghost -> crush -> leak ramp -> saturated shadows ->
// light edge dissolve -> glow -> chroma split -> vignette -> dither
void main() {
    vec2 uv = texCoord;
    vec3 src = texture(InSampler, uv).rgb;

    // double exposure: shifted copy, per-channel x offset, screened back
    vec2 guv = uv + vec2(0.035, -0.07);
    vec3 ghost;
    ghost.r = texture(InSampler, guv + vec2(0.003, 0.0)).r;
    ghost.g = texture(InSampler, guv).g;
    ghost.b = texture(InSampler, guv - vec2(0.003, 0.0)).b;
    vec3 col = 1.0 - (1.0 - clamp(src * 1.08, 0.0, 1.0)) * (1.0 - ghost * 0.22);

    col = hardCurve(col, 0.32, 0.87, 2.0);
    col = rampBlend(col, 1.0 - uv.y, 0.80 * Params.y);
    col = satBoost(col, 1.55);
    col = tintShadows(col, vec3(1.0, 0.15, 0.65), 0.40);

    float seed = floor(GameTime * 4800.0) + 53.0;
    col = edgeDress(col, uv, seed, 0.30, 0.07);
    col = localContrast(col, uv, 0.90);
    col = halation(col, uv, 0.55 * Params.w, vec3(1.0, 0.28, 0.86));
    col = chromaSplit(col, uv, 0.0035);
    col = vignette(col, uv, 0.66);
    col = posterizeDither(col, 12.0, 0.009, uv, seed);

    fragColor = vec4(mix(src, clamp(col, 0.0, 1.0), clamp(Params.x, 0.0, 1.0)), 1.0);
}
