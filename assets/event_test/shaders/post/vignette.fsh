#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:globals.glsl>

uniform sampler2D InSampler;

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 InSize;
};

layout(std140) uniform VignetteConfig {
    vec4 Tint;  // rgb = tint colour, a = strength
};

layout(location = 0) in vec2 texCoord;

layout(location = 0) out vec4 fragColor;

void main() {
    vec4 color = texture(InSampler, texCoord);

    // 0 at screen centre, 1 towards the edges
    float d = distance(texCoord, vec2(0.5));
    float vignette = smoothstep(0.30, 0.85, d);

    // slow pulse to prove GameTime drives animation (~0.5 Hz)
    float pulse = 0.85 + 0.15 * sin(GameTime * 3000.0);

    // keep the scene readable: tint toward Tint.rgb at the edges,
    // preserving a little of the original luminance
    float lum = dot(color.rgb, vec3(0.299, 0.587, 0.114));
    vec3 edgeColor = mix(Tint.rgb * (0.3 + 0.7 * lum), color.rgb, 0.15);
    vec3 outColor = mix(color.rgb, edgeColor, vignette * Tint.a);

    fragColor = vec4(outColor * pulse, 1.0);
}
