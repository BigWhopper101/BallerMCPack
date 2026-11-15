#version 330
#extension GL_ARB_separate_shader_objects : require

// Cinematic letterbox ("cinebars"): two black bars that slide in from the top
// and bottom edges of the screen and hold, with a diagnostic variant that
// draws a clock needle instead of a plain held frame.
//
// TIMING. Post effects get NO dynamic uniforms - only SamplerInfo and Globals -
// so the server cannot say "start now", and stepping a bus channel would move
// the bars at the 20 Hz command rate, which reads as judder on a hard black
// edge. So the slide is driven by the world clock instead:
//
//     GameTime = (world age mod 24000 + partialTick) / 24000      [26.3]
//
// Client level gameTime is synced from the server (ClientboundSetTimePacket ->
// ClientLevel.setTimeFromServer -> setGameTime), so the two clocks agree to
// within about a tick plus RTT. The server bakes its trigger tick into
// Params.x and picks one of 20 pre-built phase variants; the shader derives
// "ticks since the trigger" from that and animates at frame rate.
//
// Because the trigger tick is baked into a 0..23999 clock, elapsed time is
// taken inside a short window (Timing.x, e.g. 80 ticks); the controller swaps
// the effect for the static "hold" variant once the slide is done, well before
// the window could wrap back to the start.
//
// DEGRADATION. If the client clock disagrees with the baked start, elapsed
// time lands somewhere arbitrary: the bars wobble into place and the controller
// still swaps in the hold variant a few seconds later, so the *end state* is
// always right. Params.w = 1 is the clock diagnostic that proves the two clocks
// agree (also /cinebars diag).

#include <minecraft:globals.glsl>
#include <event_test:bus.glsl>

uniform sampler2D InSampler;

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 InSize;
};

layout(std140) uniform CineConfig {
    // x = start tick (world age mod 24000)
    // y = +1 slide in, -1 slide out, 0 = static hold
    // z = duration in ticks
    // w = 1 to draw the clock diagnostic needle, 0 for plain bars
    vec4 Params;
    // x = top bar thickness, y = bottom bar thickness,
    // z = unused (kept for the generator), w = edge feather in px
    vec4 Bars;
    // x = elapse window (ticks), y = lag compensation (ticks)
    vec4 Timing;
};

layout(location = 0) in vec2 texCoord;

layout(location = 0) out vec4 fragColor;

// 1 inside [lo, hi], with a feather/2 px soft edge on each side.
float barMask(float v, float lo, float hi, float feather) {
    return smoothstep(lo - feather, lo + feather, v)
         * (1.0 - smoothstep(hi - feather, hi + feather, v));
}

void main() {
    vec2 pix = floor(texCoord * OutSize);
    vec4 src = texture(InSampler, texCoord);

    // The bus decodes into a 16x16 px marker region at the bottom-left corner.
    // Painting black over it would hand garbage to every other stacked effect,
    // so that region is passed through untouched - but only while a bus is
    // actually live, so the bars stay solid when nothing else is stacked.
    if (busSync(InSampler) > 0.5 && busInRegion(pix)) {
        fragColor = src;
        return;
    }

    // ---- reveal: 0 = bars fully offscreen, 1 = bars fully in --------------
    float reveal = 1.0;
    if (Params.y != 0.0) {
        // Timing.y absorbs the client's clock lag: without it a client a tick
        // or two behind would compute an elapsed time just below zero, wrap to
        // the end of the window and snap the bars in instead of sliding.
        float d = mod(GameTime * 24000.0 - Params.x + Timing.y, max(Timing.x, 1.0));
        float p = clamp(d / max(Params.z, 1.0), 0.0, 1.0);
        float s = p * p * (3.0 - 2.0 * p);          // smoothstep: gentle at both ends
        reveal = (Params.y < 0.0) ? (1.0 - s) : s;
    }
    if (Params.w > 0.5) {
        reveal = 1.0;                                // diagnostic shows the held state
    }

    float hT = Bars.x;
    float hB = Bars.y;
    float feather = (Bars.w > 0.0 ? Bars.w : 0.5) / max(OutSize.y, 1.0);

    // top bar enters from the top edge, bottom bar from the bottom edge
    float so = (1.0 - reveal) * hT;
    float sb = (1.0 - reveal) * hB;
    float m = max(barMask(texCoord.y, 1.0 - hT + so, 1.0 + so, feather),
                  barMask(texCoord.y, -sb, hB - sb, feather));

    vec3 col = mix(src.rgb, vec3(0.0), clamp(m, 0.0, 1.0));

    // ---- diagnostic needle: the client's own world clock -------------------
    if (Params.w > 0.5) {
        float w = OutSize.x;
        float dx = abs(pix.x + 0.5 - GameTime * w);
        float needle = 1.0 - smoothstep(1.0, 2.5, dx);

        float tenth = w / 10.0;
        float dxt = mod(pix.x + 0.5, tenth);
        dxt = min(dxt, tenth - dxt);
        float tick = (pix.y < 26.0 && pix.y > 14.0) ? (1.0 - smoothstep(1.0, 2.0, dxt)) : 0.0;

        col = mix(col, vec3(0.15, 0.75, 1.0), needle);
        col = mix(col, vec3(1.0, 1.0, 1.0), tick);
    }

    fragColor = vec4(col, 1.0);
}
