#ifndef EVENT_TEST_BUS_GLSL
#define EVENT_TEST_BUS_GLSL

// Command bus geometry: 2x2 px blocks in an 8x8 grid at the screen's
// bottom-left* corner (a 16x16 px region). texCoord y=0 is the BOTTOM
// (GL convention), so block row 0 sits at the bottom of the screen.
// 64 blocks are addressable; used bits:
//
//   0..9   u   flare screen x   (10 bit = 1024 steps, ~2.5 px at 1440p)
//   10..19 v   flare screen y   (10 bit)
//   20..24 i   flare intensity  (5 bit)
//   25..29 s   shake strength   (5 bit)
//   30..34 b   blur strength    (5 bit)
//   35..39 w   warp strength    (5 bit)
//   40..42 k   flare look      (3 bit -> 4 looks)
//   43..56     (free)
//   57..62 h   heat / distortion strength                  (6 bit)
//   63     sync block (painted by a_init, bottom-right block of the grid)
//
// du/dv/t are how the flare stays smooth between 20 Hz bus updates: the
// shader reads GameTime (which advances per FRAME, in ticks) and draws the
// flash at uv + velocity * (now - stamp), i.e. dead reckoning, corrected by
// every packet. No marker entity, no occlusion, no window, no dropouts.
//
// 10-bit u/v (instead of the old 5-bit) is what makes the followed anchor
// look continuous: 5 bit snapped the point to 1/31 of the screen, so a
// moving anchor visibly hopped in ~60 px jumps at 1080p. Binary counting
// means a small move only flips the low bits either way, so the extra
// precision costs practically no extra /posteffect commands.
//
// Rules for bus-aware shaders: decode BEFORE transforming, and pass the
// region through untouched so later consumers can still read it (z_finish
// cleans it up at the end of the stack).

#define BUS_COLS 8
#define BUS_SYNC_BLOCK 63

#define BUS_U 0
#define BUS_V 10
#define BUS_I 20
#define BUS_S 25
#define BUS_B 30
#define BUS_W 35
#define BUS_K 40
#define BUS_H 57

float busBit(sampler2D s, int n) {
    ivec2 origin = ivec2(n % BUS_COLS, n / BUS_COLS) * 2;
    return step(0.5, texelFetch(s, origin, 0).r);
}

float busSync(sampler2D s) {
    return busBit(s, BUS_SYNC_BLOCK);
}

float busBits(sampler2D s, int base, int count) {
    float v = 0.0;
    for (int k = 0; k < count; k++) {
        v += busBit(s, base + k) * pow(2.0, float(k));
    }
    return v;
}

float busChannel10(sampler2D s, int base) { return busBits(s, base, 10) / 1023.0; }
float busChannel6(sampler2D s, int base) { return busBits(s, base, 6) / 63.0; }
float busChannel5(sampler2D s, int base) { return busBits(s, base, 5) / 31.0; }
float busChannel3(sampler2D s, int base) { return busBits(s, base, 3) / 7.0; }

bool busInRegion(vec2 pix) {
    return pix.x < 16.0 && pix.y < 16.0;
}

#endif
