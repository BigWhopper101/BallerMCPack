#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:globals.glsl>
#include <event_test:bus.glsl>

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

// Warp zoom-blur whose strength is driven by command bus channel 5 (w).
// With the bus live the channel is authoritative (0 = invisible -> real
// fades); without the bus it runs at full configured strength.
void main() {
    vec2 pix = floor(texCoord * OutSize);
    if (busInRegion(pix)) {
        fragColor = texture(InSampler, texCoord);
        return;
    }

    float sync = busSync(InSampler);
    float strengthScale = (sync > 0.5) ? busChannel5(InSampler, BUS_W) : 1.0;

    float pulse = Params.w + (1.0 - Params.w) * (0.5 + 0.5 * sin(GameTime * 6.2831853 * Params.z));

    vec2 dir = texCoord - 0.5;
    float reach = 0.22 * Params.x * pulse * strengthScale;

    vec3 acc = vec3(0.0);
    for (int i = 0; i < 8; i++) {
        float wt = float(i) / 7.0;
        acc += texture(InSampler, texCoord - dir * wt * reach).rgb;
    }
    acc /= 8.0;

    float cd = length(dir);
    float cs = Params.y * 0.012 * (0.25 + cd) * strengthScale;
    acc.r = mix(acc.r, texture(InSampler, texCoord + dir * cs).r, 0.85);
    acc.b = mix(acc.b, texture(InSampler, texCoord - dir * cs).b, 0.85);

    acc *= 1.0 + 0.18 * pulse * cd * strengthScale;

    // fade to clean scene at zero strength
    vec3 base = texture(InSampler, texCoord).rgb;
    fragColor = vec4(mix(base, acc, clamp(strengthScale * 1.0, 0.0, 1.0)), 1.0);
}
