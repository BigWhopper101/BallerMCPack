#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:globals.glsl>

uniform sampler2D InSampler;

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 InSize;
};

layout(std140) uniform FxConfig {
    vec4 Params;  // x = intensity, y = decay rate, z = streak amount, w = loops per day
};

layout(location = 0) in vec2 texCoord;

layout(location = 0) out vec4 fragColor;

void main() {
    // Demo note: loops every (1200 / w) seconds so the envelope is visible on repeat.
    // For a real explosion, the server steps intensity variants instead (one-shot).
    float loopT = fract(GameTime * Params.w);
    float sec = loopT * (1200.0 / Params.w);
    float env = exp(-Params.y * sec) * Params.x;

    // radial smear while the flash is hot
    vec2 dir = texCoord - 0.5;
    vec3 col = texture(InSampler, texCoord - dir * 0.020 * env).rgb;
    col += texture(InSampler, texCoord - dir * 0.050 * env).rgb;
    col += texture(InSampler, texCoord - dir * 0.090 * env).rgb;
    col /= 3.0;

    // anamorphic-style rays radiating out of the blast
    float ang = atan(dir.y, dir.x);
    float streak = pow(abs(sin(ang * 6.0 + sec * 2.0)), 8.0) * Params.z * env;

    // shockwave ring racing outward
    float d = length(dir);
    float ring = smoothstep(0.03, 0.0, abs(d - sec * 0.55)) * env * 0.5;

    vec3 outCol = mix(col, vec3(1.0), clamp(env, 0.0, 1.0));
    outCol += streak * vec3(1.0, 0.95, 0.85);
    outCol += ring * vec3(0.55, 0.75, 1.0);

    fragColor = vec4(outCol, 1.0);
}
