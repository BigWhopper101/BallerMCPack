#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:globals.glsl>

uniform sampler2D InSampler;

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 InSize;
};

layout(std140) uniform FxConfig {
    vec4 Params;  // x = block col (0-7), y = block row (0-1), z = on (0/1), w = reserved
};

layout(location = 0) in vec2 texCoord;

layout(location = 0) out vec4 fragColor;

// One bus bit: overwrites its own 2x2 px block inside the 16x4 marker
// region with white (on) or black (off). 16 blocks = 8x2 grid:
//   blocks  0-4  = U value (5 bits)
//   blocks  5-9  = V value (5 bits)
//   blocks 10-14 = I value (5 bits)
//   block  15    = sync (painted by businit)
void main() {
    vec4 scene = texture(InSampler, texCoord);
    vec2 pix = floor(texCoord * OutSize);

    vec2 origin = Params.xy * 2.0;
    float inBlock = step(origin.x - 0.5, pix.x) * step(pix.x, origin.x + 1.5)
                  * step(origin.y - 0.5, pix.y) * step(pix.y, origin.y + 1.5);

    fragColor = mix(scene, vec4(vec3(Params.z), 1.0), inBlock);
}
