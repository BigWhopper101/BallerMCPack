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
    vec4 Params;  // x,y = max amplitude (uv), z = freq (cycles/day), w = wobble ratio
};

layout(location = 0) in vec2 texCoord;

layout(location = 0) out vec4 fragColor;

// Bus-driven screen shake (channel 3 = s). Amplitude scales 0..1 with the
// channel; without a live bus it runs at full configured amplitude.
// The UV offset lives in the FRAGMENT shader (not the vertex shader) so
// the bus marker region can pass through untouched per-pixel.
void main() {
    vec2 pix = floor(texCoord * OutSize);
    if (busInRegion(pix)) {
        fragColor = texture(InSampler, texCoord);
        return;
    }

    float sync = busSync(InSampler);
    float s = (sync > 0.5) ? busChannel5(InSampler, BUS_S) : 1.0;

    float t = GameTime * 6.2831853 * Params.z;
    vec2 off = vec2(sin(t), cos(t * Params.w)) * Params.xy * s;

    fragColor = texture(InSampler, texCoord + off);
}
