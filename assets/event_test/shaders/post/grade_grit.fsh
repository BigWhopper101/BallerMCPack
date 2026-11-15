#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:globals.glsl>
#include <event_test:grade.glsl>

layout(std140) uniform FxConfig {
    vec4 Params;  // x = overall mix with the untouched frame, y = ramp strength x, z = unused, w = glow x
};

layout(location = 0) in vec2 texCoord;
layout(location = 0) out vec4 fragColor;

// y_grit: hard crush -> warm leak ramp -> saturated shadows ->
// edge dissolve + hue fringe -> glow -> chroma split -> vignette -> dither
void main() {
    vec2 uv = texCoord;
    vec3 src = texture(InSampler, uv).rgb;

    vec3 col = clamp(src * 1.10, 0.0, 1.0);
    col = streakDrag(col, uv, 0.40, 0.10);
    col = hardCurve(col, 0.34, 0.86, 2.1);
    col = rampBlend(col, 1.0 - uv.y, 0.80 * Params.y);
    col = satBoost(col, 1.55);
    col = tintShadows(col, vec3(1.0, 0.15, 0.65), 0.40);

    float seed = floor(GameTime * 4800.0);
    col = edgeDress(col, uv, seed, 0.45, 0.10);
    col = localContrast(col, uv, 0.90);
    col = halation(col, uv, 0.55 * Params.w, vec3(1.0, 0.28, 0.86));
    col = chromaSplit(col, uv, 0.004);
    col = vignette(col, uv, 0.68);
    col = posterizeDither(col, 12.0, 0.009, uv, seed);

    fragColor = vec4(mix(src, clamp(col, 0.0, 1.0), clamp(Params.x, 0.0, 1.0)), 1.0);
}
