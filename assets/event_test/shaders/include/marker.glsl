#ifndef EVENT_TEST_MARKER_GLSL
#define EVENT_TEST_MARKER_GLSL

// Magenta marker key.
//
// The server keeps a billboard `item_display` entity at the anchor whose item
// model is a flat quad textured pure magenta (1, 0, 1) at full brightness.
// Entity lighting scales all three channels by the same lightmap factor and
// tonemapping is absent, so the HUE survives: min(r,b) - g stays near 1.0 for
// the marker.
//
// This is how the flash gets a position that needs no server-side projection:
// the marker is detected in the frame that is actually being rendered, so
// FOV, aspect and camera staleness cannot affect it.
//
// The key has to be strict, because purple/blue scenery (amethyst, terracotta,
// glazed terracotta, magenta wool) also has r ~= b with low-ish green and
// otherwise reads as "magenta". Conditions, all relative to the pixel's own
// brightness so entity diffuse shading (0.45..1.0) cannot break it:
//   - not pitch black              min(r,b) >= ~0.3
//   - red and blue nearly equal    |r - b| < 0.08
//   - green clearly suppressed     g < 0.2 * min(r,b)
// Bright magenta scenery sits at g = 0.25..0.4 of its red, so it misses.

float markerScore(vec3 c) {
    float m = min(c.r, c.b);
    float bal = abs(c.r - c.b);
    return clamp(m - c.g, 0.0, 1.0)
         * smoothstep(0.20, 0.35, m)
         * (1.0 - smoothstep(0.05, 0.09, bal))
         * (1.0 - smoothstep(0.18, 0.26, c.g / max(m, 0.001)));
}

#endif
