#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:globals.glsl>

uniform sampler2D InSampler;
uniform sampler2D FlareSampler;

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 InSize;
};

layout(std140) uniform FxConfig {
    vec4 Params;  // x = min brightness, y = intensity, z = ghost amount, w = streak amount
};

layout(location = 0) in vec2 texCoord;

layout(location = 0) out vec4 fragColor;

// Lens flare built from the brightest spot in the tiny Flare buffer:
// ghosts along the optical axis, anamorphic streak, halo ring, starburst.
void main() {
    vec3 base = texture(InSampler, texCoord).rgb;
    float aspect = OutSize.x / max(OutSize.y, 1.0);

    // 1. find brightest texel in the 8x8 bright-pass buffer
    float bestL = -1.0;
    vec2 bestUv = vec2(0.5);
    for (int y = 0; y < 8; y++) {
        for (int x = 0; x < 8; x++) {
            vec3 s = texelFetch(FlareSampler, ivec2(x, y), 0).rgb;
            float l = dot(s, vec3(0.299, 0.587, 0.114));
            if (l > bestL) {
                bestL = l;
                bestUv = (vec2(float(x), float(y)) + 0.5) / 8.0;
            }
        }
    }

    float bright = max(bestL - Params.x, 0.0);
    if (bright <= 0.0) {
        fragColor = vec4(base, 1.0);
        return;
    }

    vec2 fp = bestUv;
    vec2 d = fp - vec2(0.5);
    float flare = 0.0;
    vec3 tint = vec3(0.0);

    // 2. ghosts: coloured circles along the line through screen centre
    float gScales[3];
    gScales[0] = 0.55; gScales[1] = 1.45; gScales[2] = 2.10;
    vec3 gTints[3];
    gTints[0] = vec3(0.4, 0.7, 1.0);
    gTints[1] = vec3(1.0, 0.6, 0.3);
    gTints[2] = vec3(0.5, 1.0, 0.6);
    for (int k = 0; k < 3; k++) {
        vec2 gp = vec2(0.5) + d * gScales[k];
        float r = length((texCoord - gp) * vec2(aspect, 1.0));
        float ghost = smoothstep(0.075, 0.0, r) * 0.6
                    + smoothstep(0.16, 0.0, r) * 0.15;
        flare += ghost * 0.5;
        tint += gTints[k] * ghost;
    }

    // 3. halo ring roughly opposite the light
    vec2 hp = vec2(0.5) - d * 0.55;
    float hr = length((texCoord - hp) * vec2(aspect, 1.0));
    float halo = smoothstep(0.02, 0.0, abs(hr - 0.22)) * 0.5;
    flare += halo;
    tint += vec3(1.0, 0.85, 0.6) * halo;

    // 4. anamorphic horizontal streak through the light
    float streak = exp(-abs(texCoord.y - fp.y) * 90.0)
                 * exp(-abs(texCoord.x - fp.x) * 1.6);
    flare += streak * Params.w;
    tint += vec3(0.6, 0.8, 1.0) * streak;

    // 5. starburst rays
    vec2 rel = (texCoord - fp) * vec2(aspect, 1.0);
    float dist = length(rel);
    float ang = atan(rel.y, rel.x);
    float rays = pow(abs(sin(ang * 4.0)), 24.0) * exp(-dist * 5.0) * 0.8;
    flare += rays;
    tint += vec3(1.0, 0.95, 0.8) * rays;

    vec3 outCol = base + tint * (bright * Params.y) + vec3(flare * 0.15) * bright;
    fragColor = vec4(outCol, 1.0);
}
