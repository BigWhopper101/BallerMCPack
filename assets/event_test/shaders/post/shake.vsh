#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:globals.glsl>

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 InSize;
};

layout(std140) uniform ShakeConfig {
    vec4 ShakeParams;  // x,y = amplitude (uv units), z = frequency (cycles per day), w = wobble ratio
};

layout(location = 0) out vec2 texCoord;

void main() {
    vec2 uv = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
    gl_Position = vec4(uv * vec2(2, 2) + vec2(-1, -1), 0, 1);

    // GameTime runs 0..1 over one in-game day (~20 min real time)
    float t = GameTime * 6.2831853 * ShakeParams.z;
    vec2 offset = vec2(
        sin(t),
        cos(t * ShakeParams.w)
    ) * ShakeParams.xy;

    texCoord = uv + offset;
}
