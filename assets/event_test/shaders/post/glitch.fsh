#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:globals.glsl>

uniform sampler2D InSampler;

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 InSize;
};

layout(std140) uniform FxConfig {
    vec4 Params;  // x = displacement, y = rgb split, z = noise blocks, w = bursts per day
};

layout(location = 0) in vec2 texCoord;

layout(location = 0) out vec4 fragColor;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

void main() {
    float bt = GameTime * Params.w;          // burst clock
    float seed = floor(bt);
    float within = fract(bt);

    // bursts come and go; each one flickers then dies out
    float burst = step(0.45, hash(vec2(seed, 3.7)));
    float bEnv = burst * smoothstep(1.0, 0.55, within);

    // horizontal band displacement
    float seg = floor(texCoord.y * 24.0);
    float r1 = hash(vec2(seg, floor(bt * 24.0)));
    float off = (r1 - 0.5) * 0.18 * Params.x * bEnv;

    // rgb split follows the displacement
    float split = 0.006 * Params.y * bEnv;
    vec3 col;
    col.r = texture(InSampler, texCoord + vec2(off + split, 0.0)).r;
    col.g = texture(InSampler, texCoord).g;
    col.b = texture(InSampler, texCoord + vec2(off * 0.6 - split, 0.0)).b;

    // scanlines
    col *= 0.88 + 0.12 * sin(texCoord.y * OutSize.y * 3.14159);

    // noise blocks (datamosh cells)
    vec2 cell = floor(texCoord * vec2(32.0, 18.0));
    float nb = step(0.92, hash(cell + seed * 7.0)) * bEnv;
    vec3 noiseCol = vec3(hash(cell * 1.73 + vec2(seed, 1.0)));
    col = mix(col, noiseCol, nb * Params.z);

    // slow rolling bar
    float bar = smoothstep(0.025, 0.0, abs(fract(texCoord.y + GameTime * 3.0) - 0.5));
    col += bar * 0.08 * (0.3 + bEnv);

    fragColor = vec4(col, 1.0);
}
