#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:globals.glsl>

uniform sampler2D InSampler;

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 InSize;
};

layout(location = 0) in vec2 texCoord;

layout(location = 0) out vec4 fragColor;

// Bus cleanup: restores the 16x16 px marker region by copying pixels from
// just to the right of it (18 px in, so the source is always outside the
// region). Apply this effect LAST in the stack (after all bus consumers)
// so no marker pixels reach the screen.
void main() {
    vec2 pix = floor(texCoord * OutSize);
    float inRegion = step(pix.x, 15.0) * step(pix.y, 15.0);

    vec2 srcUv = texCoord + vec2(18.0 / InSize.x, 0.0);
    vec4 patched = texture(InSampler, srcUv);

    fragColor = mix(texture(InSampler, texCoord), patched, inRegion);
}
