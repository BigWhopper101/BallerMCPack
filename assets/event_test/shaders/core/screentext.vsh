#version 330
#extension GL_ARB_separate_shader_objects : require

// Screen text vertex stage: the SAME screenquad quad, but clipped to the
// effect's rect instead of covering the screen.
//
// WHY THIS EXISTS. A full-screen post pass costs OutSize.x * OutSize.y fragment
// invocations, and a line of text is 10-50 of those passes stacked - at 1080p
// that was ~120 M invocations per frame, which is why typing lagged and a full
// terminal panel dragged the frame rate down. Drawing the quad only over the
// glyph (a ~30x30 px box, 1/1000 of the screen) makes the cost proportional to
// the ink instead of the screen.
//
// The quad is snapped to whole pixels so the companion copy pass samples texel
// for texel - no half-pixel blur, no seam.

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 InSize;
};

layout(std140) uniform StConfig {
    vec4 Cell;   // glyph cell origin/size, or the box height (see below)
    vec4 Rect;   // x,y = centre uv, z = half width uv, w = MODE
    vec4 Look;
    vec4 Ink;
};

layout(location = 0) out vec2 texCoord;

// Box height, per mode. MUST MATCH screentext.fsh - the two passes have to
// agree on the rect or the copy pass resamples the wrong pixels.
//   0-4  glyph: square in pixels (an atlas cell is square)
//   5    plate: Cell.x is half height / half width in uv (a uv ratio)
//   6    panel: Cell.x is the PNG's height / width in PIXELS, so the art keeps
//        its proportions at any window shape. A uv ratio stretched with the
//        window, which is what made the banner look wide.
//   7    bar: Cell.x > 0 is the half height in uv; Cell.x < 0 is a pixel ratio,
//        for a bar that has to match a panel exactly
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

void main() {
    int mode = int(Rect.w + 0.5);

    vec2 centre = Rect.xy * OutSize;
    float halfX = Rect.z * OutSize.x;
    float halfY = halfHeight(mode);

    vec2 lo = floor(centre - vec2(halfX, halfY));
    vec2 hi = ceil(centre + vec2(halfX, halfY));

    vec2 uv = vec2((gl_VertexIndex << 1) & 2, gl_VertexIndex & 2);
    vec2 p = mix(lo, hi, uv);

    gl_Position = vec4(p / OutSize * 2.0 - 1.0, 0.0, 1.0);
    texCoord = p / OutSize;
}
