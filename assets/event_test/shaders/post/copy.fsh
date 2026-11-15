#version 330
#extension GL_ARB_separate_shader_objects : require

// Screen text copy pass: blit swap -> main, but only over the rect the quad
// covers (screentext.vsh). Same job as minecraft:post/blit, minus the
// BlitConfig uniform block the text passes have no use for.

uniform sampler2D InSampler;

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 InSize;
};

layout(location = 0) in vec2 texCoord;

layout(location = 0) out vec4 fragColor;

void main() {
    // texCoord is the pixel's CORNER, so a corner sample lands between four
    // texels. Inside the quad swap holds what the first pass wrote, but just
    // outside it swap still holds whatever an earlier effect left there - and
    // blending that in put a one-pixel fringe along every box edge. Sample the
    // centre of the texel this pixel owns instead: a straight copy, hard edge.
    vec2 uv = (floor(texCoord * OutSize) + 0.5) / OutSize;
    fragColor = texture(InSampler, uv);
}
