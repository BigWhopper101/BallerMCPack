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
    vec4 Params;  // x,y = blur direction, z = max radius (px), w = reserved
};

layout(location = 0) in vec2 texCoord;

layout(location = 0) out vec4 fragColor;

// Bus-driven box blur (channel 4 = b). Two passes (H then V) with the
// radius scaled 0..max by the channel. The marker region passes through
// unblurred so the second pass can still decode the bus.
void main() {
    vec2 pix = floor(texCoord * OutSize);
    if (busInRegion(pix)) {
        fragColor = texture(InSampler, texCoord);
        return;
    }

    float sync = busSync(InSampler);
    float b = (sync > 0.5) ? busChannel5(InSampler, BUS_B) : 1.0;
    float radius = Params.z * b;

    if (radius < 0.5) {
        fragColor = texture(InSampler, texCoord);
        return;
    }

    float actualRadius = round(max(radius, 1.0));
    vec2 oneTexel = 1.0 / InSize;
    vec2 sampleStep = oneTexel * Params.xy;

    // relies on bilinear sampling: step of 2 with half weight at the end
    vec4 blurred = vec4(0.0);
    for (float a = -actualRadius + 0.5; a <= actualRadius; a += 2.0) {
        blurred += texture(InSampler, texCoord + sampleStep * a);
    }
    blurred += texture(InSampler, texCoord + sampleStep * actualRadius) / 2.0;
    fragColor = blurred / (actualRadius + 0.5);
}
