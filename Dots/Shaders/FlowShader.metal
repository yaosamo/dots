#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// A port of onlook.com's header ("Flow gradient", a Unicorn Studio scene): a near-black gradient,
// ink that trails the pointer tinted by the direction it moved, and slow domain-warped noise that
// marbles both. Onlook runs three WebGL passes and keeps the ink in a ping-pong texture; SwiftUI
// shaders have no memory between frames, so here the ink is redrawn every frame from the pointer's
// recent path (see PointerTrail in Onboarding/FlowBackground.swift), aging, sliding and spreading
// with time the way the feedback buffer would. Works in their coordinates: uv 0…1 across and up.

// MARK: Their noise

static float3 flowHash33(float3 p3) {
    p3 = fract(p3 * float3(0.1031, 0.11369, 0.13787));
    p3 += dot(p3, p3.yxz + 19.19);
    return -1.0 + 2.0 * fract(float3((p3.x + p3.y) * p3.z, (p3.x + p3.z) * p3.y, (p3.y + p3.z) * p3.x));
}

/// Gradient noise, roughly -0.9…0.9.
static float flowPerlin(float3 p) {
    float3 i = floor(p);
    float3 f = p - i;
    float3 w = f * f * (3.0 - 2.0 * f);
    float n000 = dot(f, flowHash33(i));
    float n100 = dot(f - float3(1, 0, 0), flowHash33(i + float3(1, 0, 0)));
    float n010 = dot(f - float3(0, 1, 0), flowHash33(i + float3(0, 1, 0)));
    float n110 = dot(f - float3(1, 1, 0), flowHash33(i + float3(1, 1, 0)));
    float n001 = dot(f - float3(0, 0, 1), flowHash33(i + float3(0, 0, 1)));
    float n101 = dot(f - float3(1, 0, 1), flowHash33(i + float3(1, 0, 1)));
    float n011 = dot(f - float3(0, 1, 1), flowHash33(i + float3(0, 1, 1)));
    float n111 = dot(f - float3(1, 1, 1), flowHash33(i + float3(1, 1, 1)));
    return mix(mix(mix(n000, n100, w.x), mix(n010, n110, w.x), w.y),
               mix(mix(n001, n101, w.x), mix(n011, n111, w.x), w.y), w.z);
}

/// Six octaves, each turned half a radian and 2.5× finer, gain 0.594 (their "turbulence" 0.76).
static float flowFbm(float3 st) {
    const float2x2 turn = float2x2(float2(cos(0.5), sin(0.5)), float2(-sin(0.5), cos(0.5))) * 2.5;
    float value = 0.0;
    float amplitude = 0.25;
    for (int i = 0; i < 6; i++) {
        value += amplitude * flowPerlin(st);
        st.xy = st.xy * turn + 100.0;
        amplitude *= 0.594;
    }
    return value;
}

static float2 flowRotate(float2 p, float angle) {
    float s = sin(angle), c = cos(angle);
    return float2(p.x * c - p.y * s, p.x * s + p.y * c);
}

static float flowRandom(float2 p) {
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

// MARK: Their gradient

/// Mixes two sRGB colors through OKLab, as Unicorn Studio does, so dark stops don't go muddy.
static float3 flowOklabMix(float3 a, float3 b, float t) {
    const float3x3 toLms = float3x3(float3(0.4121656120, 0.2118591070, 0.0883097947),
                                    float3(0.5362752080, 0.6807189584, 0.2818474174),
                                    float3(0.0514575653, 0.1074065790, 0.6302613616));
    const float3x3 fromLms = float3x3(float3(4.0767245293, -1.2681437731, -0.0041119885),
                                      float3(-3.3072168827, 2.6093323231, -0.7034763098),
                                      float3(0.2307590544, -0.3411344290, 1.7068625689));
    float3 lmsA = pow(max(toLms * pow(a, 2.2), 0.0), 1.0 / 3.0);
    float3 lmsB = pow(max(toLms * pow(b, 2.2), 0.0), 1.0 / 3.0);
    float3 lms = mix(lmsA, lmsB, t) * (1.0 + 0.025 * t * (1.0 - t));
    return pow(max(fromLms * (lms * lms * lms), 0.0), 1.0 / 2.2);
}

/// Three stops at 0, ½ and 1 along a line turned by `angle` turns, mirrored past the ends (which,
/// as in theirs, puts the first stop at the far end).
static float3 flowGradient(float2 uv, float angle, float3 c0, float3 c1, float3 c2) {
    float along = flowRotate(uv - 0.5, (angle - 0.5) * 2.0 * M_PI_F).x + 0.5;
    float t = abs(fract(along * 0.5) * 2.0 - 1.0);
    return t < 0.5 ? flowOklabMix(c0, c1, t * 2.0) : flowOklabMix(c1, c2, t * 2.0 - 1.0);
}

static float3 flowHue(float hue) {
    float3 p = abs(fract(hue + float3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
    return clamp(p - 1.0, 0.0, 1.0);
}

// MARK: The shader

/// - size: view size in points. time: seconds, for the marbling.
/// - trail, trailCount: the pointer's recent path, oldest first, as (x, y, age in seconds) with
///   x, y in 0…1 across and up the view, about a frame apart while the pointer moves. A
///   gap of over 0.1 s between points breaks the stroke.
/// - top, middle, bottom: the gradient's stops (sRGB). angle: its direction, in turns.
/// - accent: the ink's color. accentMix: 0 ink is all rainbow-by-direction, 1 all accent.
/// - brush: ink width (screen heights). sharpness: its falloff. inkSpeed: pointer speed (screen
///   heights a second) for full ink. intensity: ink brightness. life: seconds for ink to fade to a
///   third. spread: how much it widens as it ages. advect: how fast ink keeps sliding along its
///   stroke. liquify: how much it wobbles as it ages.
/// - warp: the marbling's strength (1 is Onlook's). warpScale: its size (theirs 0.15). flow: speed.
/// - paint: 0 adds ink as light (for dark backgrounds, like Onlook), 1 lays it on as paint (for
///   light ones). fade: overall opacity.
[[ stitchable ]] half4 welcomeFlow(float2 position, half4 color, float2 size, float time,
                                   device const float *trail, int trailCount,
                                   float3 top, float3 middle, float3 bottom, float angle,
                                   float3 accent, float accentMix,
                                   float brush, float sharpness, float inkSpeed, float intensity,
                                   float life, float spread, float advect, float liquify,
                                   float warp, float warpScale, float flow, float paint, float fade) {
    float aspect = size.x / size.y;
    float2 stretch = float2(aspect, 1.0); // to screen heights, so the brush stays round
    float2 uv = float2(position.x / size.x, 1.0 - position.y / size.y);

    // The marbling (their fbm pass): a double domain warp around the point they chose. Their uTime
    // runs at 9 a second (60 × speed 0.15), hence 0.225 and 0.0648 a second here.
    float2 center = float2(0.5686, 0.6511);
    float multiplier = 6.0 * (warpScale / ((aspect + 1.0) / 2.0));
    float2 st = flowRotate((uv - center) * stretch * multiplier * aspect, -0.135 * 2.0 * M_PI_F);
    float2 drift = float2(time * flow * 0.0648);
    float z = time * flow * 0.225;
    float2 r = float2(flowFbm(float3(st - drift + float2(1.7, 9.2), z)),
                      flowFbm(float3(st - drift + float2(8.2, 1.3), z)));
    float f = flowFbm(float3(st + r - drift, z)) * 0.31;
    float2 marbled = uv + (f * 2.0 + r * 0.31) * warp;

    float3 col = flowGradient(marbled, angle, top, middle, bottom);
    col += flowRandom(position) * 0.005; // dither, so the dark gradient doesn't band

    // The ink (their mouseDraw pass), from the path instead of a feedback texture.
    float2 here = marbled * stretch;
    float2 wobble = float2(flowPerlin(float3(here * 6.0, 0.0)), flowPerlin(float3(here * 6.0 + 17.0, 0.0)));
    float3 hues = float3(0.0);
    float amount = 0.0;
    int points = trailCount / 3;
    for (int i = 1; i < points; i++) {
        float3 a = float3(trail[i * 3 - 3], trail[i * 3 - 2], trail[i * 3 - 1]);
        float3 b = float3(trail[i * 3], trail[i * 3 + 1], trail[i * 3 + 2]);
        float2 move = (b.xy - a.xy) * stretch;
        float moved = length(move);
        // Nothing between a pause, or the pointer leaving and coming back, and the next move.
        if (moved < 1e-5 || a.z - b.z > 0.1) { continue; }
        float2 heading = move / moved;
        float speed = moved / max(a.z - b.z, 1.0 / 120.0);

        // Ink keeps sliding along its stroke, slowing as it fades (their per-frame advection).
        float2 start = a.xy * stretch + heading * advect * life * (1.0 - exp(-a.z / life));
        float2 end = b.xy * stretch + heading * advect * life * (1.0 - exp(-b.z / life));

        float2 span = end - start;
        float along = clamp(dot(here - start, span) / max(dot(span, span), 1e-8), 0.0, 1.0);
        float age = mix(a.z, b.z, along);
        float gap = distance(here + wobble * liquify * min(age, 1.5), start + span * along);
        float radius = brush * (1.0 + spread * age);
        if (gap > radius * 12.0) { continue; } // too far to matter
        float weight = pow(radius / (gap + radius), sharpness) * exp(-age / life) * min(speed / inkSpeed, 1.0);

        hues += pow(flowHue(fract(atan2(heading.y, heading.x) / (2.0 * M_PI_F))), 2.2) * weight;
        amount += weight;
    }
    float ink = 1.0 - exp(-amount); // piles up, but saturates the way the feedback buffer does
    float3 hue = hues / max(amount, 1e-5);

    // Their composite adds strength² × mix(hue × strength, accent): bright where the ink is thick,
    // soft at its edges. Painting instead covers the background with the ink's color.
    float3 lit = col + ink * ink * intensity * mix(hue * ink, accent, accentMix);
    float3 painted = mix(col, mix(hue, accent, accentMix), min(ink * ink * intensity, 1.0));
    col = min(mix(lit, painted, paint), 1.0);
    return half4(half3(col * fade), half(fade));
}
