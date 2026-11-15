#version 330
#extension GL_ARB_separate_shader_objects : require

// Screen text ("screentext"): one glyph of one line, drawn as a post effect
// pass over the finished frame - plus the non-glyph modes that reuse the same
// geometry (a backdrop plate, and the frame transformed through the letters).
//
// WHY ONE EFFECT PER GLYPH. /posteffect takes only an effect id, post shaders
// get no dynamic uniforms, and UniformValue has no array type - so the server
// cannot send "draw BALLERMC, here, this big". What it *can* do is stack
// effects, and every effect gets its own baked constants. So the pack ships
// glyph x position (x row x column), each a tiny JSON that differs only in an
// atlas cell and a screen rectangle. A message is then a handful of
// `/posteffect add` calls and the *content* stays arbitrary at runtime - which
// is the point over a baked caption image or a /title.
//
// NO TRIGGER CLOCK NEEDED. A line is built from discrete add/remove events, so
// the reveal is just "add the next glyph every few ticks" - the command stream
// IS the typewriter, at 20 Hz, and a letter appearing is a step event anyway
// (unlike cine.fsh, where a *continuously moving* bar could not be stepped at
// 20 Hz and had to have its start tick baked into the effect id). Only the
// shimmer and the cursor blink read Globals.GameTime, and both are continuous,
// so nothing needs baking or syncing.
//
// MODES (Rect.w, so one shader serves all of them):
//   0  ink                     the glyph, with halo and drop shadow
//   1  invert stencil          frame inverted through the glyph
//   2  ink + blink             the terminal cursor (off the world clock)
//   3  desaturate stencil      frame desaturated through the glyph
//   4  posterise stencil       frame quantised through the glyph
//   5  plate                   a solid matte behind the text (Cell.x = the
//                              rect's half-height as a fraction of its
//                              half-width, in uv)
//   6  panel                   a UI panel PNG (bezel, title box)
//                              stretched over the rect
//   7  bar                     a solid bar the width of a line of text; the
//                              controller shows it for a few ticks, then
//                              swaps it for the text (the reveal)
//
// RENDER ORDER. Post effects run before the GUI, so this sits over the world
// but UNDER the hud/chat/crosshair - same as every other postfx effect. Stack
// order matters: a plate has to be added before the glyphs it sits behind.

#include <minecraft:globals.glsl>
#include <event_test:bus.glsl>

// Must match gen_stext.py (CELL / SDF_RANGE): the atlas stores a distance
// field, and these two numbers are what turn it back into an edge. Drift here
// is not a compile error - check_stext.py compares them against the generator.
#define ATLAS_CELL 128.0   // px per glyph cell in the atlas
#define SDF_RANGE 16.0     // stored px of distance per 1.0 of alpha

uniform sampler2D InSampler;
uniform sampler2D GlyphSampler;

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 InSize;
};

layout(std140) uniform StConfig {
    // x,y = atlas cell origin in uv, z,w = atlas cell size in uv. v=0 is the
    // TOP row of the PNG (textures upload row 0 first), hence the -rel.y below.
    // In plate mode (5) x carries the rect half-height / half-width ratio and
    // the rest is unused.
    vec4 Cell;
    // x,y = box centre in uv, z = half width in uv, w = MODE
    vec4 Rect;
    // x = glow strength, y = scanline strength, z = rgb split in px, w = alpha
    vec4 Look;
    // xyz = ink colour, w = drop-shadow strength (small type needs more of it
    // to stay legible over a bright scene)
    vec4 Ink;
};

layout(location = 0) in vec2 texCoord;

layout(location = 0) out vec4 fragColor;

// Box height, per mode. MUST MATCH screentext.vsh: the copy pass has to place
// the quad over exactly the pixels this pass wrote, or its edges resample.
//   0-4  glyph   square in pixels
//   5    plate   Cell.x = half height / half width in uv
//   6    panel   Cell.x = PNG height / width in PIXELS (no stretch)
//   7    bar     Cell.x > 0: half height in uv.  Cell.x < 0: pixel ratio
float halfHeight(int mode) {
    if (mode == 6) {
        return max(abs(Cell.x), 0.02) * Rect.z * OutSize.x;
    }
    if (mode == 7) {
        return Cell.x > 0.0 ? Cell.x * OutSize.y
                            : -Cell.x * Rect.z * OutSize.x;
    }
    if (mode == 5) {
        return max(Cell.x, 0.02) * Rect.z * OutSize.y;
    }
    return Rect.z * OutSize.x;
}

// CRT grid: one soft line every three pixels, aligned to the frame. The plate,
// the banner face and the ink all ride this ONE grid - two different periods
// beat against each other and read as noise rather than as a screen.
float crtScan(float y) {
    return 0.5 + 0.5 * cos(y * 2.0943951);      // 2*pi/3: a 3 px period
}

// rel is a -1..1 box coordinate; the atlas stores signed distance in alpha
// (0.5 = edge, 1.0 of alpha = 2*SDF_RANGE atlas px), so coverage is a
// smoothstep on it.
float coverage(vec2 rel, float aa) {
    vec2 auv = Cell.xy + vec2(rel.x * 0.5 + 0.5, 0.5 - rel.y * 0.5) * Cell.zw;
    float sdf = texture(GlyphSampler, auv).a;
    return smoothstep(0.5 - aa, 0.5 + aa, sdf);
}

float signedDistance(vec2 rel) {
    vec2 auv = Cell.xy + vec2(rel.x * 0.5 + 0.5, 0.5 - rel.y * 0.5) * Cell.zw;
    return texture(GlyphSampler, auv).a;
}

void main() {
    vec2 pix = floor(texCoord * OutSize);
    // Sample the frame at the PIXEL CENTRE. texCoord is the pixel's corner
    // (the quad is snapped to whole pixels), so sampling with it lands exactly
    // between four texels: every pass blended the frame 50/50 with its
    // neighbours and all 20-odd stacked effects did it again, so a solid box
    // came out with a soft, dirty fringe down its sides.
    vec2 uv = (pix + 0.5) / OutSize;
    vec4 src = texture(InSampler, uv);
    int mode = int(Rect.w + 0.5);

    // The command bus decodes into a 16x16 px marker region at the bottom-left.
    // Painting over it would hand garbage to every stacked effect that reads
    // it, so that region passes through untouched - only while a bus is live,
    // so the text is not truncated by an invisible marker when nothing is up.
    if (busSync(InSampler) > 0.5 && busInRegion(pix)) {
        fragColor = src;
        return;
    }

    vec2 centre = Rect.xy * OutSize;
    float halfX = Rect.z * OutSize.x;               // px
    float halfY = halfHeight(mode);
    vec2 rel = (pix - centre) / vec2(halfX, max(halfY, 1.0));

    // Outside the box this pass is a no-op.
    if (abs(rel.x) > 1.0 || abs(rel.y) > 1.0) {
        fragColor = src;
        return;
    }

    // ---- bar: the reveal block, exactly as wide as the text it hides --------
    if (mode == 7) {
        // hard-edged on purpose: this is a one-tick flash, a feathered edge
        // would just read as blur
        fragColor = vec4(mix(src.rgb, Ink.xyz, Look.w), src.a);
        return;
    }

    // ---- panel: the console chrome, from panel.png --------------------------
    if (mode == 6) {
        vec2 tuv = vec2(rel.x * 0.5 + 0.5, 0.5 - rel.y * 0.5);
        vec4 pan = texture(GlyphSampler, tuv);
        // the grid is multiplicative here: the face is already lit, and dark
        // lines break up the slab of green instead of adding light to it. The
        // vignette darkens it toward the bezel so it reads as a lit screen
        // rather than as a flat swatch of colour.
        float vig = 1.0 - 0.35 * pow(max(abs(rel.x), abs(rel.y)), 3.0);
        pan.rgb *= vig * (1.0 - Look.y * crtScan(pix.y));
        fragColor = vec4(mix(src.rgb, pan.rgb, pan.a * Look.w), src.a);
        return;
    }

    // ---- plate: a flat matte behind the text ------------------------------
    if (mode == 5) {
        float edge = min(1.0 - abs(rel.x), 1.0 - abs(rel.y));
        float px = edge * min(halfX, halfY);
        float m = smoothstep(0.0, 2.0, px) * Look.w;
        // The fade-in. Post effects get no dynamic uniforms, so the ramp runs
        // off the world clock the client already syncs: Cell.y is a baked
        // start tick within the 24000-tick day, Cell.z the duration, Cell.w
        // the wrap window. The controller adds the slice it is starting in and
        // swaps in the static plate before the window can wrap.
        // A negative Cell.z ramps DOWN instead: the same slice grid fades the
        // black out again before the event starts.
        if (Cell.w > 0.0 && abs(Cell.z) > 0.0) {
            float d = mod(GameTime * 24000.0 - Cell.y + 2.0, Cell.w);
            float p = clamp(d / abs(Cell.z), 0.0, 1.0);
            float s = p * p * (3.0 - 2.0 * p);  // smoothstep: gentle both ends
            m *= (Cell.z > 0.0) ? s : (1.0 - s);
        }
        vec3 col = src.rgb * (1.0 - m);
        // additive on purpose: a multiplied line on a black plate is black,
        // and the grid has to be visible against the black
        col += Ink.xyz * crtScan(pix.y) * Look.y * m;
        fragColor = vec4(col, src.a);
        return;
    }

    float cellPx = 2.0 * halfX;                     // the atlas cell on screen
    // One screen px is ATLAS_CELL/cellPx atlas px, and 1.0 of alpha spans
    // 2*SDF_RANGE atlas px, so this is a ~1.2 px soft edge at any resolution.
    float aa = 1.2 * (ATLAS_CELL / cellPx) / (2.0 * SDF_RANGE);

    // Chromatic split: coverage sampled slightly left/centre/right, one channel
    // from each. Look.z = 0 (the clean look) makes all three samples identical.
    float split = Look.z / halfX;                   // px -> rel units
    float aL = coverage(rel - vec2(split, 0.0), aa);
    float aC = coverage(rel, aa);
    float aR = coverage(rel + vec2(split, 0.0), aa);
    vec3 fringe = vec3(mix(aC, aL, 0.55), aC, mix(aC, aR, 0.55));
    float cover = max(aC, max(aL, aR));

    // Drop shadow: sampling up-left makes the ink land down-right. Cheap (one
    // SDF tap) and it is what keeps the type legible over sky or a whiteout.
    float aS = coverage(rel + vec2(2.0, 3.0) / halfX, aa);
    if (cover <= 0.001 && aS <= 0.001) {
        fragColor = src;
        return;
    }

    // ---- stencils: the glyph is a mask, not ink ---------------------------
    if (mode == 1) {
        vec3 inverted = 1.0 - src.rgb;
        vec3 rim = Ink.xyz * (1.0 - abs(2.0 * cover - 1.0)) * 0.35;
        fragColor = vec4(mix(src.rgb, inverted, cover * Look.w) + rim, src.a);
        return;
    }
    if (mode == 3) {
        float luma = dot(src.rgb, vec3(0.299, 0.587, 0.114));
        fragColor = vec4(mix(src.rgb, vec3(luma), cover * Look.w), src.a);
        return;
    }
    if (mode == 4) {
        vec3 post = floor(src.rgb * 4.0 + 0.5) / 4.0;
        fragColor = vec4(mix(src.rgb, post, cover * Look.w), src.a);
        return;
    }

    // ---- ink -------------------------------------------------------------
    // Blink mode: the cursor, 1 s period off GameTime (ticks) - the controller
    // places it, the clock blinks it, no server involvement per frame.
    float blink = 1.0;
    if (mode == 2) {
        blink = 0.10 + 0.90 * step(0.5, fract(GameTime * 1200.0));
        if (blink <= 0.11) {
            fragColor = src;
            return;
        }
    }

    // Glow falloff straight out of the SDF - no blur taps. The halo radius
    // tracks the glyph size, so it looks the same at 720p and 4K.
    float sdf = signedDistance(rel);
    float outPx = sdf < 0.5
        ? (0.5 - sdf) * (2.0 * SDF_RANGE) * (cellPx / ATLAS_CELL) : 0.0;
    float halo = exp(-outPx / max(halfX * 0.17, 1.0));

    // Emissive shimmer: enough to read as light, not as a sprite. GameTime is
    // in ticks and advances per frame, so this is frame-smooth with no server.
    float shimmer = 0.94 + 0.06 * sin(GameTime * 41.0 + rel.x * 2.3);
    float scan = 1.0 - Look.y * 0.5 * crtScan(pix.y);

    vec3 ink = Ink.xyz * shimmer * scan;
    vec3 glyph = ink * fringe;

    float a = cover * Look.w * blink;
    vec3 col = mix(src.rgb * (1.0 - aS * Ink.w), glyph, a);
    col += Ink.xyz * shimmer * halo * Look.x * 0.45 * blink;

    fragColor = vec4(col, src.a);
}
