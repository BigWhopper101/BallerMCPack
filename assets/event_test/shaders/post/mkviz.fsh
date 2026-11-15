#version 330
#extension GL_ARB_separate_shader_objects : require

#include <minecraft:globals.glsl>
#include <event_test:bus.glsl>
#include <event_test:marker.glsl>

uniform sampler2D InSampler;
uniform sampler2D MkSampler;
uniform sampler2D MkPosSampler;

layout(std140) uniform SamplerInfo {
    vec2 OutSize;
    vec2 InSize;
    vec2 MkSize;
    vec2 MkPosSize;
};

layout(location = 0) in vec2 texCoord;

layout(location = 0) out vec4 fragColor;

// DIAGNOSTIC effect: /postfx apply c_mkviz
//
// Coded for shape first, colour second, and only along the blue/yellow axis -
// no red/green pair that colourblind eyes can confuse:
//   BLUE tint           = marker pixels present in the frame
//   WHITE hollow box    = position the find pass reported (detection worked)
//   YELLOW thin cross   = position commanded over the bus (projection path)
//
// Nothing is drawn over the marker itself, so a missing blue patch means the
// entity is not rendering (or is rendering in a non-magenta colour).
void main() {
    vec2 pix = floor(texCoord * OutSize);
    vec3 base = texture(InSampler, texCoord).rgb;
    if (busInRegion(pix)) {
        fragColor = vec4(base, 1.0);
        return;
    }
    float aspect = OutSize.x / max(OutSize.y, 1.0);

    vec4 hit = texture(MkPosSampler, vec2(0.5));
    bool have = hit.b > 0.3;

    float sync = busSync(InSampler);
    vec2 busUV = vec2(busChannel10(InSampler, BUS_U), busChannel10(InSampler, BUS_V));

    vec3 col = base;

    // marker pixels: saturated blue
    float key = markerScore(base);
    col = mix(col, vec3(0.10, 0.35, 1.00), clamp(key * 4.0, 0.0, 0.85));

    // detection result: hollow white box around the reported point
    if (have) {
        vec2 d2 = abs((texCoord - hit.rg) * OutSize);
        float m2 = max(d2.x, d2.y);
        float box = (1.0 - step(9.0, m2)) * step(6.0, m2);
        col = mix(col, vec3(1.0), box);
    }

    // bus projection: thin yellow crosshair
    if (sync > 0.5) {
        vec2 rp = abs((texCoord - busUV) * vec2(aspect, 1.0));
        float c = (smoothstep(0.0016, 0.0, rp.x) + smoothstep(0.0016, 0.0, rp.y))
                * smoothstep(0.09, 0.0, length(rp));
        col = mix(col, vec3(1.0, 0.8, 0.0), clamp(c, 0.0, 1.0));
    }

    fragColor = vec4(col, 1.0);
}
