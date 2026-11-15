// Shared helpers for the photographic GRADES (event_test:grade_grit / grade_combo).
// Mirrored 1:1 from the numpy look-dev harness (lookdev5.py) so what was judged
// off-line is what renders in-game.

uniform sampler2D InSampler;

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 InSize;
};

float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

vec3 rgb2hsv(vec3 c) {
    vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
    vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
    vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
    float d = q.x - min(q.w, q.y);
    float e = 1.0e-10;
    return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
    vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float vnoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i), b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0)), d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

vec3 satBoost(vec3 c, float m) {
    vec3 h = rgb2hsv(clamp(c, 0.0, 1.0));
    return hsv2rgb(vec3(h.x, clamp(h.y * m, 0.0, 1.0), h.z));
}

// exposure -> optional vertical drag -> contrast crush
vec3 streakDrag(vec3 col, vec2 uv, float strength, float lengthV) {
    vec3 acc = vec3(0.0);
    float wsum = 0.0;
    for (int i = 1; i <= 6; i++) {
        float fi = float(i);
        float off = lengthV * pow(fi / 6.0, 1.7);
        float w = pow(1.0 - fi / 7.0, 2.0);
        acc += texture(InSampler, uv + vec2(0.0, off)).rgb * w;
        wsum += w;
    }
    return mix(col, acc / max(wsum, 1.0e-4), strength);
}

vec3 hardCurve(vec3 c, float black, float white, float contrast) {
    vec3 x = clamp((clamp(c, 0.0, 1.0) - black) / max(1.0e-3, white - black), 0.0, 1.0);
    vec3 y = x * x * (3.0 - 2.0 * x);
    return clamp(x + (y - x) * contrast, 0.0, 1.0);
}

// warm leak ramp: bottom red -> pink -> white -> mauve -> violet  (t = 0 at bottom)
vec3 leakWarm(float t) {
    t = clamp(t, 0.0, 1.0);
    vec3 a = vec3(1.00, 0.10, 0.45);
    vec3 b = vec3(1.00, 0.25, 0.55);
    vec3 c = vec3(1.00, 0.85, 0.95);
    vec3 d = vec3(0.95, 0.55, 0.90);
    vec3 e = vec3(0.60, 0.20, 0.85);
    if (t < 0.35) return mix(a, b, smoothstep(0.0, 0.35, t));
    if (t < 0.62) return mix(b, c, smoothstep(0.35, 0.62, t));
    if (t < 0.85) return mix(c, d, smoothstep(0.62, 0.85, t));
    return mix(d, e, smoothstep(0.85, 1.0, t));
}

// "color" blend: hue+sat from the ramp, brightness from the frame
vec3 rampBlend(vec3 col, float t, float amount) {
    vec3 layer = leakWarm(t);
    vec3 lh = rgb2hsv(clamp(layer, 0.0, 1.0));
    vec3 ch = rgb2hsv(clamp(col, 0.0, 1.0));
    vec3 tinted = hsv2rgb(vec3(lh.x, clamp(lh.y, 0.0, 1.0), ch.z));
    return mix(col, tinted, clamp(amount, 0.0, 1.0));
}

// screen a saturated colour into the darks only
vec3 tintShadows(vec3 col, vec3 tint, float amount) {
    float m = (1.0 - smoothstep(0.0, 0.55, luma(col))) * amount;
    vec3 c = clamp(tint * m, 0.0, 1.0);
    return 1.0 - (1.0 - col) * (1.0 - c);
}

// gradient magnitude of luma at 1.5 px, 0..1
float edgeMap(vec2 uv) {
    vec2 px = 1.5 / InSize;
    float l0 = luma(texture(InSampler, uv + vec2(px.x, 0.0)).rgb);
    float l1 = luma(texture(InSampler, uv - vec2(px.x, 0.0)).rgb);
    float l2 = luma(texture(InSampler, uv + vec2(0.0, px.y)).rgb);
    float l3 = luma(texture(InSampler, uv - vec2(0.0, px.y)).rgb);
    return clamp((abs(l0 - l1) + abs(l2 - l3)) * 8.0, 0.0, 1.0);
}

vec3 edgeDress(vec3 col, vec2 uv, float seed, float diss, float fringe) {
    if (diss <= 0.001 && fringe <= 0.001) return col;
    float e = edgeMap(uv);
    float n1 = hash21(floor(uv * InSize) + seed) - 0.5;
    float n2 = vnoise(uv * InSize / 4.0 + seed) - 0.5;
    vec3 g = clamp(col + ((n1 * 1.6 + n2 * 0.8) * e * diss), 0.0, 1.0);
    g *= (1.0 - 0.22 * e);
    if (fringe > 0.001) {
        vec3 h = rgb2hsv(clamp(g, 0.0, 1.0));
        float d = (n1 * fringe + n2 * fringe * 0.5) * smoothstep(0.04, 0.5, e);
        float sat = h.y * (1.0 + 0.9 * smoothstep(0.08, 0.55, e));
        g = hsv2rgb(vec3(fract(h.x + d), clamp(sat, 0.0, 1.0), h.z));
    }
    return g;
}

vec3 localContrast(vec3 col, vec2 uv, float amount) {
    vec2 px = 2.0 / InSize;
    vec3 blur = (
        texture(InSampler, uv + vec2(px.x, 0.0)).rgb +
        texture(InSampler, uv - vec2(px.x, 0.0)).rgb +
        texture(InSampler, uv + vec2(0.0, px.y)).rgb +
        texture(InSampler, uv - vec2(0.0, px.y)).rgb +
        texture(InSampler, uv + vec2(px.x, px.y)).rgb +
        texture(InSampler, uv + vec2(-px.x, px.y)).rgb +
        texture(InSampler, uv + vec2(px.x, -px.y)).rgb +
        texture(InSampler, uv + vec2(-px.x, -px.y)).rgb
    ) * 0.125;
    return clamp(col + (col - blur) * amount, 0.0, 1.0);
}

// pink-tinted glow: bright pass, 12 taps on two rings, screen back
vec3 halation(vec3 col, vec2 uv, float strength, vec3 tint) {
    float thresh = 0.55;
    vec3 acc = vec3(0.0);
    float wsum = 0.0;
    for (int i = 0; i < 12; i++) {
        float a = float(i) * 0.5236;           // 30 deg steps
        float r = (i < 6) ? 0.012 : 0.030;
        vec2 o = vec2(cos(a), sin(a)) * r * vec2(1.0, 0.62);
        vec3 s = texture(InSampler, uv + o).rgb;
        float b = max(0.0, luma(s) - thresh) / (1.0 - thresh);
        float w = (i < 6) ? 0.075 : 0.0917;
        acc += s * b * w;
        wsum += w;
    }
    vec3 glow = clamp(acc / max(wsum, 1.0e-4), 0.0, 1.0) * tint * strength;
    return 1.0 - (1.0 - col) * (1.0 - glow);
}

vec3 chromaSplit(vec3 col, vec2 uv, float amount) {
    if (amount <= 0.0001) return col;
    vec2 d = (uv - 0.5) * amount;
    col.r = texture(InSampler, uv + d).r;
    col.b = texture(InSampler, uv - d).b;
    return col;
}

vec3 vignette(vec3 col, vec2 uv, float amount) {
    float r = length((uv - 0.5) * 2.0) / 1.4142;
    return col * (1.0 - amount * pow(clamp(r, 0.0, 1.0), 1.4));
}

vec3 posterizeDither(vec3 col, float levels, float dith, vec2 uv, float seed) {
    vec3 n = vec3(hash21(uv * InSize + seed),
                  hash21(uv * InSize + seed + 17.0),
                  hash21(uv * InSize + seed + 41.0)) - 0.5;
    return floor((clamp(col, 0.0, 1.0) + n * dith * 2.0) * (levels - 1.0) + 0.5) / (levels - 1.0);
}
