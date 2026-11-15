#version 330
#extension GL_ARB_separate_shader_objects : require

// Cutscene screen shake: the shader layer that sits ON TOP of the native
// camera-rotation shake (which stays in incident.py for players who cannot see
// resource-pack shaders, and is deliberately weak so that this layer can be
// the strong one).
//
// Same SHAPE as incident._shake_at(), much bigger amplitudes, with one
// deliberate difference: the jolt is ATTACKED over Timing.z ticks instead of
// stepping straight to the peak. A hard step makes any small timing error read
// as "the shake fired before the explosion"; a ~250 ms smoothstep ramp into the
// peak hides a few ticks of clock slop and looks like a real impact.
//
//     t <  break            :  amp = base + (rise - base) * t / break
//     break <= t < +attack  :  amp = smoothstep(rise -> peak)
//     t >= break + attack   :  amp = max(base, peak * exp(-(t - break - attack) / decay))
//
// Amplitudes are baked in DEGREES (1 deg ~= 13.5 px of screen shift at 1080p at
// the default FOV), converted here, so the JSON numbers stay readable against
// the native ones.
//
// The offset is mostly VERTICAL: with a letterbox on screen the vertical part
// is hidden behind the bars, so it can be large without smearing the frame
// edges, while a big horizontal offset would drag clamped edge pixels across
// the picture. A small second harmonic breaks up the pure-sine look.
//
// Timing comes from the world clock, like the letterbox: the break tick is
// baked into the effect id (see gen_cine.py), because post shaders get no
// dynamic uniforms.
//
//     GameTime = (world age mod 24000 + partialTick) / 24000      [26.3]

#include <minecraft:globals.glsl>
#include <event_test:bus.glsl>

uniform sampler2D InSampler;

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 InSize;
};

layout(std140) uniform ShakeConfig {
    // x = break tick (world age mod 24000: the beat the jolt lands on)
    // y = ticks from cutscene start to that break
    // z = attack: ticks to ramp from rise to peak (0 = hard step)
    // w = lag compensation (ticks); 0 unless calibrated
    vec4 Timing;
    // x = base amplitude (deg), y = rise amplitude (deg),
    // z = peak amplitude (deg), w = decay (ticks)
    vec4 Envelope;
    // x = frequency (cycles/day), y = wobble ratio,
    // z = uv per degree, w = x share of the offset (0 = purely vertical)
    vec4 Wave;
    // x = elapse window (ticks) the baked break tick is periodic over
    // y = fold tolerance: elapsed times within this of a full window are read
    //     as "slightly negative" (client clock a few ticks behind) rather than
    //     as "almost a whole window has passed"
    vec4 Span;
};

layout(location = 0) in vec2 texCoord;

layout(location = 0) out vec4 fragColor;

// second harmonic: fraction of the main amplitude, and the worst-case sum used
// to size the overscan below
const float HARM = 0.28;

void main() {
    vec2 pix = floor(texCoord * OutSize);

    // Never shift the postfx bus marker region, or its consumers decode
    // garbage. Only meaningful while a bus is live, so with no bus stacked
    // the shake covers the whole screen.
    if (busSync(InSampler) > 0.5 && busInRegion(pix)) {
        fragColor = texture(InSampler, texCoord);
        return;
    }

    // Ticks since the cutscene started: 0 at the trigger, Timing.y at the jolt.
    //
    // The baked break tick is only meaningful MODULO Span.x (there is one
    // variant per phase of that window), so the difference has to be wrapped -
    // without it, a world tick of 20000 against a break of 66 reads as an
    // elapsed time of 20054 and every envelope is already over. The wrap is
    // then folded for values just below the window, so a client whose clock is
    // a tick or two behind reads as "not started yet" instead of "wrapped past
    // the end" (which would swallow the jolt).
    float now = GameTime * 24000.0;
    float window = max(Span.x, 1.0);
    float d = mod(now - Timing.x + Timing.y + Timing.w, window);
    if (d > window - max(Span.y, 0.0)) d -= window;
    float since = max(d, 0.0);

    float brk = max(Timing.y, 1.0);
    float atk = max(Timing.z, 0.0);
    float amp;
    if (since < brk) {
        amp = Envelope.x + (Envelope.y - Envelope.x) * clamp(since / brk, 0.0, 1.0);
    } else if (since < brk + atk) {
        float f = clamp((since - brk) / atk, 0.0, 1.0);
        f = f * f * (3.0 - 2.0 * f);
        amp = Envelope.y + (Envelope.z - Envelope.y) * f;
    } else {
        amp = max(Envelope.x,
                  Envelope.z * exp(-(since - brk - atk) / max(Envelope.w, 1.0)));
    }

    float uvAmp = amp * Wave.z;
    float xShare = Wave.w;
    float t = GameTime * 6.2831853 * Wave.x;

    // The harmonic is vertical-only: the vertical offset hides behind the
    // letterbox bars, while anything added horizontally would have to be
    // covered by more overscan zoom (see below).
    vec2 off = vec2(sin(t) * xShare, cos(t * Wave.y)) * uvAmp
             + vec2(0.0, cos(t * 3.11 + 0.4)) * (uvAmp * HARM);

    // Overscan: zoom in just far enough that the horizontal offset can never
    // sample outside the frame (that would smear clamped edge pixels across the
    // picture). Horizontal travel is exactly uvAmp * xShare, so covering twice
    // that is enough; the vertical part is hidden by the bars and needs none.
    float cover = 2.0 * uvAmp * xShare;
    vec2 uv = (texCoord - 0.5) * (1.0 - cover) + 0.5 + off;

    fragColor = texture(InSampler, uv);
}
