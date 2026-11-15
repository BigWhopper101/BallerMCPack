#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:globals.glsl>

uniform sampler2D InSampler;

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 InSize;
};

layout(std140) uniform FxConfig {
    vec4 Params;  // x = active seconds, y = red splash, z = frames per second, w = loops per day
};

layout(location = 0) in vec2 texCoord;

layout(location = 0) out vec4 fragColor;

// Manga "impact frames": hard two-tone posterisation with strobing inversion
// and red edge splashes, active for a short window each loop.
void main() {
    float loopT = fract(GameTime * Params.w);
    float secPerLoop = 1200.0 / Params.w;
    float onWindow = step(loopT * secPerLoop, Params.x);
    float frame = floor(loopT * secPerLoop * Params.z);
    float inv = mod(frame, 2.0);

    vec3 c = texture(InSampler, texCoord).rgb;
    float lum = dot(c, vec3(0.299, 0.587, 0.114));

    // threshold jitters a little per frame for a hand-drawn feel
    float th = 0.5 + 0.08 * sin(frame * 2.3);
    float poster = step(th, lum);
    poster = abs(poster - inv);
    vec3 ink = mix(vec3(0.02), vec3(1.0), poster);

    // edge accent from a cheap luminance gradient
    float lx = dot(texture(InSampler, texCoord + vec2(1.5 / InSize.x, 0.0)).rgb, vec3(0.333));
    float ly = dot(texture(InSampler, texCoord + vec2(0.0, 1.5 / InSize.y)).rgb, vec3(0.333));
    float edge = smoothstep(0.10, 0.30, abs(lum - lx) + abs(lum - ly));
    ink = mix(ink, vec3(1.0, 0.08, 0.08), edge * Params.y);

    vec3 outCol = mix(c, ink, onWindow);
    fragColor = vec4(outCol, 1.0);
}
