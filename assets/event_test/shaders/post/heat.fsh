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
    vec4 Params;  // x = amplitude, y = scroll speed, z = chroma, w = noise scale
};

layout(location = 0) in vec2 texCoord;

layout(location = 0) out vec4 fragColor;

float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float vnoise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash(i);
    float b = hash(i + vec2(1.0, 0.0));
    float c = hash(i + vec2(0.0, 1.0));
    float d = hash(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// Heat haze: procedural noise distortion rising from below, with chroma split.
// Strength comes from bus channel h (6 bit) so it fades in/out like the other
// consumers; without a live bus it runs at full configured strength.
// This is a "vague" effect - a 20 Hz channel is plenty, nothing here is
// anchored to a point in the world.
void main() {
    vec2 pix = floor(texCoord * OutSize);
    if (busInRegion(pix)) {
        fragColor = texture(InSampler, texCoord);
        return;
    }

    float sync = busSync(InSampler);
    float h = (sync > 0.5) ? busChannel6(InSampler, BUS_H) : 1.0;
    if (h < 0.01) {
        fragColor = texture(InSampler, texCoord);
        return;
    }

    float t = GameTime * 1200.0 * Params.y;   // ~seconds scale
    vec2 p = texCoord * Params.w * vec2(OutSize.x / max(OutSize.y, 1.0), 1.0);

    float n1 = vnoise(p + vec2(0.0, -t * 0.8));
    float n2 = vnoise(p * 2.3 + vec2(t * 0.5, -t * 1.4));
    vec2 disp = (vec2(n1, n2) - 0.5) * Params.x * h;

    // heat rises: distortion strongest near the bottom of the screen
    disp *= 0.35 + 0.65 * (1.0 - texCoord.y);

    float chroma = Params.z * h;
    vec3 col;
    col.r = texture(InSampler, texCoord + disp * (1.0 + chroma)).r;
    col.g = texture(InSampler, texCoord + disp).g;
    col.b = texture(InSampler, texCoord + disp * (1.0 - chroma)).b;

    // faint warm shimmer in the hot regions
    col += vec3(0.10, 0.035, 0.0) * n1 * h * (1.0 - texCoord.y);

    fragColor = vec4(col, 1.0);
}
