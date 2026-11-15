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

// Bus initialiser: paints the 16x16 px marker region (bottom-left of the
// screen) black, with the sync block white = "bus live". Bit effects then
// overwrite their own 2x2 blocks. Must run FIRST in the effect stack;
// "finish" cleans the region last.
void main() {
    vec4 scene = texture(InSampler, texCoord);
    vec2 pix = floor(texCoord * OutSize);

    float inRegion = step(pix.x, 15.0) * step(pix.y, 15.0);
    // sync block 63 = grid col 7, row 7 -> pixels (14..15, 14..15)
    float syncBlock = step(13.5, pix.x) * step(13.5, pix.y);

    vec4 painted = mix(vec4(0.0, 0.0, 0.0, 1.0), vec4(1.0), syncBlock);
    fragColor = mix(scene, painted, inRegion);
}
