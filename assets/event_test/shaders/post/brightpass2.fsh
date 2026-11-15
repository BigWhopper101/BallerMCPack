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
    vec4 Params;  // x = threshold, y = knee, z = sky depth cutoff, w = reserved
};

layout(location = 0) in vec2 texCoord;

layout(location = 0) out vec4 fragColor;

// Sky-gated bright pass: keeps only bright SKY pixels (depth at the far
// plane), so held items / hands / white walls can't hijack light detection.
void main() {
    vec2 texel = 1.0 / InSize;
    vec3 a = texture(InSampler, texCoord + texel * vec2(-1.5, -1.5)).rgb;
    vec3 b = texture(InSampler, texCoord + texel * vec2( 1.5, -1.5)).rgb;
    vec3 c = texture(InSampler, texCoord + texel * vec2(-1.5,  1.5)).rgb;
    vec3 d = texture(InSampler, texCoord + texel * vec2( 1.5,  1.5)).rgb;
    vec3 s = max(max(a, b), max(c, d));

    float depth = texture(MainDepthSampler, texCoord).x;
    float isSky = step(Params.z, depth);

    float lum = dot(s, vec3(0.299, 0.587, 0.114));
    float keep = smoothstep(Params.x, Params.x + max(Params.y, 0.001), lum) * isSky;

    fragColor = vec4(s * keep, 1.0);
}
