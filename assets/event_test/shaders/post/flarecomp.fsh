#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:globals.glsl>
#include <event_test:bus.glsl>
#include <event_test:marker.glsl>

uniform sampler2D InSampler;
uniform sampler2D FlareSampler;
uniform sampler2D MkSampler;
uniform sampler2D MkPosSampler;

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 InSize;
    vec2 FlareSize;
    vec2 MkSize;
    vec2 MkPosSize;
};

layout(std140) uniform FxConfig {
    vec4 Params;  // x = auto-mode min brightness, y = gain, z = screen wash, w = reticle (0 = off)
};

layout(location = 0) in vec2 texCoord;

layout(location = 0) out vec4 fragColor;

// Point flash at a selectable anchor, in priority order:
//   1. a magenta marker actually visible in the frame (see marker.glsl) -
//      exact by construction, no FOV/aspect/lag dependence at all
//   2. a screen position commanded over the command bus (u, v)
//   3. the brightest SKY pixel (auto mode)
//
// Shape is picked live over bus channel k (3 bit, 4 looks):
//   0 = soft flash (default)   1 = hard punch
//   2 = big bloom ball         3 = whiteout
//
// No ring, no rays, no ghost chain: hot core + soft falloff + a whisper of
// screen-wide lift. r is measured in screen HEIGHTS (x aspect-corrected), so
// the constants are resolution independent.

void main() {
    vec2 pix = floor(texCoord * OutSize);
    vec3 base = texture(InSampler, texCoord).rgb;
    if (busInRegion(pix)) {
        fragColor = vec4(base, 1.0);
        return;
    }
    float aspect = OutSize.x / max(OutSize.y, 1.0);

    // ---- 1. marker mode: where the magenta marker actually rendered ----
    vec4 mkHit = texture(MkPosSampler, vec2(0.5));
    bool haveMarker = mkHit.b > 0.3;
    vec2 markerUV = mkHit.rg;
    if (haveMarker) {
        // refine the coarse argmax to sub-cell accuracy from its neighbourhood
        ivec2 cell = ivec2(floor(markerUV * MkSize));
        float wsum = 0.0;
        vec2 acc = vec2(0.0);
        for (int dy = -2; dy <= 2; dy++) {
            for (int dx = -2; dx <= 2; dx++) {
                ivec2 c = cell + ivec2(dx, dy);
                if (c.x < 0 || c.y < 0 || c.x >= int(MkSize.x) || c.y >= int(MkSize.y)) continue;
                float k = texelFetch(MkSampler, c, 0).r;
                wsum += k;
                acc += (vec2(float(c.x), float(c.y)) + 0.5) * k;
            }
        }
        if (wsum > 1e-4) markerUV = (acc / wsum) / MkSize;
    }

    // hide the marker: replace its pixels with a coarse inpaint of what is
    // around them. Restricted to the neighbourhood of the detected marker, so
    // a magenta-ish block elsewhere on screen can never get punched out.
    float mkey = haveMarker ? markerScore(base) : 0.0;
    vec2 drel = (texCoord - markerUV) * vec2(aspect, 1.0);
    if (mkey > 0.15 && dot(drel, drel) < 0.03 * 0.03) {
        vec2 r = 18.0 / OutSize;
        vec3 ip = 0.25 * (texture(InSampler, texCoord + vec2(r.x, 0.0)).rgb
                        + texture(InSampler, texCoord - vec2(r.x, 0.0)).rgb
                        + texture(InSampler, texCoord + vec2(0.0, r.y)).rgb
                        + texture(InSampler, texCoord - vec2(0.0, r.y)).rgb);
        base = mix(base, ip, smoothstep(0.15, 0.5, mkey));
    }

    // ---- 2/3. bus position, or the auto sky spot ----
    float sync = busSync(InSampler);
    float u = busChannel10(InSampler, BUS_U);
    float v = busChannel10(InSampler, BUS_V);
    float inten = busChannel5(InSampler, BUS_I);
    float look = busChannel3(InSampler, BUS_K);

    float bestL = -1.0;
    vec2 bestUv = vec2(0.5);
    for (int y = 0; y < 8; y++) {
        for (int x = 0; x < 8; x++) {
            vec3 s = texelFetch(FlareSampler, ivec2(x, y), 0).rgb;
            float l = dot(s, vec3(0.299, 0.587, 0.114));
            if (l > bestL) { bestL = l; bestUv = (vec2(float(x), float(y)) + 0.5) / 8.0; }
        }
    }

    // Position is used exactly as the bus delivered it: dead reckoning is
    // dropped (see bus.glsl). 20 Hz of a 10-bit position is the practical
    // best this transport gives; extrapolating it was not worth the jitter.

    bool manual = sync > 0.5 && inten > 0.02;
    vec2 fp = haveMarker ? markerUV : (manual ? vec2(u, v) : bestUv);
    float I = haveMarker ? inten : (manual ? inten : max(bestL - Params.x, 0.0) * 1.5);
    I = clamp(I, 0.0, 1.0) * Params.y;

    vec2 rel = (texCoord - fp) * vec2(aspect, 1.0);
    float r2 = dot(rel, rel);

    int L = int(floor(clamp(look, 0.0, 0.999) * 4.0));

    // exp(-r2 * K) == gaussian with sigma = 1/sqrt(2K), expressed in screen heights
    float core, mid, wide, wash;
    vec3 coreTint, outerTint;

    if (L == 1) {                        // hard punch, camera-flash like
        core = exp(-r2 * 3200.0) * 1.60;
        mid  = exp(-r2 * 420.0) * 0.62;
        wide = exp(-r2 * 60.0) * 0.16;
        wash = 0.11;
        coreTint = vec3(1.0, 1.0, 1.0);
        outerTint = vec3(0.95, 0.97, 1.0);
    } else if (L == 2) {                 // big bloom ball
        core = exp(-r2 * 620.0) * 0.85;
        mid  = exp(-r2 * 90.0) * 0.80;
        wide = exp(-r2 * 14.0) * 0.34;
        wash = 0.04;
        coreTint = vec3(1.0, 0.97, 0.90);
        outerTint = vec3(1.0, 0.94, 0.86);
    } else if (L == 3) {                 // whiteout (screen goes white)
        core = exp(-r2 * 1400.0) * 1.80;
        mid  = exp(-r2 * 130.0) * 1.05;
        wide = exp(-r2 * 12.0) * 0.55;
        wash = 0.26;
        coreTint = vec3(1.0, 1.0, 1.0);
        outerTint = vec3(1.0, 1.0, 1.0);
    } else {                             // 0 = soft flash (default)
        core = exp(-r2 * 1500.0) * 1.20;
        mid  = exp(-r2 * 170.0) * 0.58;
        wide = exp(-r2 * 18.0) * 0.20;
        wash = 0.06;
        coreTint = vec3(1.0, 0.98, 0.93);
        outerTint = vec3(0.93, 0.96, 1.0);
    }

    vec3 col = base;

    // optional calibration crosshair exactly on the anchor
    if (Params.w > 0.001 && (haveMarker || manual)) {
        vec2 rp = abs((texCoord - fp) * vec2(aspect, 1.0));
        float ret = (smoothstep(0.0025, 0.0, rp.x) + smoothstep(0.0025, 0.0, rp.y))
                  * smoothstep(0.05, 0.0, sqrt(r2));
        col += vec3(0.85, 0.95, 1.0) * ret * Params.w;
    }

    if (I > 0.002) {
        float shape = core + mid + wide;
        // light is brightest/whitest at the core and cools slightly outwards
        vec3 tint = mix(coreTint, outerTint, clamp(1.0 - core, 0.0, 1.0));
        col = col * (1.0 + shape * I * 0.35)      // the light also lights what's behind it
            + tint * (shape * I)
            + vec3(wash * I * Params.z);
    }

    fragColor = vec4(min(col, vec3(16.0)), 1.0);
}
