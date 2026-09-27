#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
#include "Noise.h"
using namespace metal;

/// Fire around the camera bubble (see EffectRim in Camera/CameraView.swift): the pen's fire
/// (PenShaders.metal), flames licking upward off the stroke, but without its bands. The pen looks
/// for stroke below each pixel at 7 fixed steps, each fading a fixed amount, which draws layered
/// lines; here the steps are jittered per pixel and fade smoothly, so the flames are one continuous
/// shape. SwiftUI's y axis grows downward.
///
/// - height: the tallest flames, in points. speed: how fast the noise rises.
/// - wobble: how far the flames sway sideways.
[[ stitchable ]] half4 rimFire(float2 position, SwiftUI::Layer layer, float time,
                               float height, float speed, float wobble) {
    float n = fbm(float2(position.x * 0.045, position.y * 0.045 + time * speed));
    float2 p = position + float2((n - 0.5) * wobble, 0.0);
    const int taps = 14;
    float jitter = hash(position * 0.37 + 11.0);
    half heat = 0.0h;
    for (int k = 0; k < taps; k++) {
        float along = (float(k) + jitter) / float(taps);
        heat = max(heat, layer.sample(p + float2(0.0, along * height)).a * half(1.0 - along));
    }
    float turbulence = fbm(float2(position.x * 0.08, position.y * 0.08 + time * speed * 1.54));
    half h = clamp(heat * half(0.55 + 0.9 * turbulence), 0.0h, 1.0h);
    h = max(h, layer.sample(position).a * 0.9h);
    half3 color = half3(1.0h, smoothstep(0.25h, 0.9h, h) * 0.85h, smoothstep(0.7h, 1.0h, h) * 0.55h);
    half alpha = smoothstep(0.08h, 0.45h, h);
    return half4(color * alpha, alpha);
}

/// A cloud the camera bubble sits in (see CloudRim in Camera/CameraView.swift): a cluster of round
/// puffs along the bubble's bottom, over a wide soft base, blended into one shape, in front of the
/// video and spilling out past its sides and bottom. Noise roughens the outline so it's fluffy; the
/// puffs breathe and sway a little; tops are bright, lower down is soft grey-blue.
/// SwiftUI's y axis grows downward.
///
/// - size: this layer (the bubble's width plus `side` each side, its lower part plus `below`).
/// - bubble: the bubble's size. side, below: how far the cloud spills out. time: for the motion.
[[ stitchable ]] half4 cameraCloud(float2 position, half4 color, float2 size, float2 bubble,
                                   float side, float below, float time) {
    float2 p = float2(position.x - size.x * 0.5, position.y - (size.y - below)); // 0 at the bubble's bottom middle
    float h = bubble.y;
    float span = bubble.x * 0.475 + side * 0.3;

    // The base: a wide, low ellipse under the bubble's bottom.
    float2 baseRadii = float2(span * 1.02, h * 0.2);
    float d = (length(p / baseRadii) - 1.0) * min(baseRadii.x, baseRadii.y);

    // Puffs along the bottom, bigger toward the middle, each breathing and swaying on its own beat.
    const int count = 7;
    for (int i = 0; i < count; i++) {
        float t = float(i) / float(count - 1) * 2.0 - 1.0; // -1…1 across
        float jitter = hash(float2(float(i), 4.7));
        float radius = h * (0.17 + 0.12 * (1.0 - t * t) + 0.05 * jitter) * (1.0 + 0.04 * sin(time * 0.9 + float(i) * 1.7));
        float2 center = float2(t * span * 0.8 + sin(time * 0.35 + float(i)) * h * 0.02,
                               -h * (0.06 + 0.1 * (1.0 - t * t)) + (jitter - 0.5) * h * 0.06);
        float puff = length(p - center) - radius;
        // Smooth union, so the puffs flow into each other.
        float k = h * 0.09;
        float blend = clamp(0.5 + 0.5 * (puff - d) / k, 0.0, 1.0);
        d = mix(puff, d, blend) - k * blend * (1.0 - blend);
    }

    // Fluffy outline: noise pushes the edge in and out, finer at the very edge.
    float2 q = position * 0.045 + float2(time * 0.04, 0.0);
    float fluff = fbm(q, 4) - 0.5;
    d += fluff * h * 0.09;

    float soft = h * 0.035;
    float density = 1.0 - smoothstep(-soft, soft, d);
    // A little thinner at the edge of the layer so nothing is cut off square.
    density *= 1.0 - smoothstep(size.y - below * 0.25, size.y, position.y);

    // Bright on top, soft grey-blue lower down, with a hint of texture inside.
    float lower = clamp((p.y + h * 0.32) / (h * 0.5), 0.0, 1.0);
    half3 lit = mix(half3(1.0h), half3(0.83h, 0.86h, 0.92h), half(smoothstep(0.15, 1.0, lower)));
    float texture = fbm(q * 1.6 + 3.0, 3);
    lit *= half(0.95 + 0.05 * texture);
    half alpha = half(density);
    return half4(lit * alpha, alpha);
}
