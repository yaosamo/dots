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

/// A cloud the camera bubble sits in (see CloudRim in Camera/CameraView.swift): a low band of small
/// puffs along the bubble's bottom edge, wider than the bubble so its corners are always buried, with
/// bigger billows hanging down below it. Only round puffs, blended into one shape, and noise roughens
/// the outline, so there are no straight lines. The puffs breathe and sway a little; tops are bright,
/// the hanging billows soft grey-blue. SwiftUI's y axis grows downward.
///
/// - size: this layer (the bubble's width plus `side` each side; a little above its bottom plus `below`).
/// - bubble: the bubble's size. side, below: how far the cloud spills out. time: for the motion.
[[ stitchable ]] half4 cameraCloud(float2 position, half4 color, float2 size, float2 bubble,
                                   float side, float below, float time) {
    float2 p = float2(position.x - size.x * 0.5, position.y - (size.y - below)); // 0 at the bubble's bottom middle
    float w = bubble.x; // sized from the width, so a tall bubble doesn't get a giant cloud
    float span = w * 0.5 + side * 0.55;
    float k = w * 0.05; // how smoothly the puffs flow into each other

    float d = 1e5;
    // Across the bubble's bottom edge: small puffs, a little bigger toward the middle.
    const int top = 8;
    for (int i = 0; i < top; i++) {
        float t = float(i) / float(top - 1) * 2.0 - 1.0; // -1…1 across
        float jitter = hash(float2(float(i), 4.7));
        float radius = w * (0.095 + 0.035 * (1.0 - t * t) + 0.02 * jitter) * (1.0 + 0.05 * sin(time * 0.9 + float(i) * 1.7));
        float2 center = float2(t * span * 0.9 + sin(time * 0.35 + float(i)) * w * 0.012,
                               -w * (0.06 + 0.03 * (1.0 - t * t)) + (jitter - 0.5) * w * 0.03);
        float puff = length(p - center) - radius;
        float blend = clamp(0.5 + 0.5 * (puff - d) / k, 0.0, 1.0);
        d = mix(puff, d, blend) - k * blend * (1.0 - blend);
    }
    // Hanging below: fewer, bigger billows.
    const int hanging = 5;
    for (int i = 0; i < hanging; i++) {
        float t = float(i) / float(hanging - 1) * 2.0 - 1.0;
        float jitter = hash(float2(float(i), 9.3));
        float radius = w * (0.1 + 0.03 * (1.0 - t * t) + 0.025 * jitter) * (1.0 + 0.04 * sin(time * 0.7 + float(i) * 2.3));
        float2 center = float2(t * span * 0.68 + (jitter - 0.5) * w * 0.05 + sin(time * 0.3 + float(i) * 1.3) * w * 0.012,
                               w * (0.03 + 0.02 * jitter));
        float puff = length(p - center) - radius;
        float blend = clamp(0.5 + 0.5 * (puff - d) / k, 0.0, 1.0);
        d = mix(puff, d, blend) - k * blend * (1.0 - blend);
    }

    // Fluffy outline: noise pushes the edge in and out.
    float2 q = position * 0.05 + float2(time * 0.04, 0.0);
    d += (fbm(q, 4) - 0.5) * w * 0.05;
    float soft = w * 0.02;
    float density = 1.0 - smoothstep(-soft, soft, d);

    // Bright on top, soft grey-blue in the hanging billows, with a hint of texture.
    float lower = clamp((p.y + w * 0.1) / (w * 0.3), 0.0, 1.0);
    half3 lit = mix(half3(1.0h), half3(0.83h, 0.86h, 0.92h), half(smoothstep(0.2, 1.0, lower)));
    lit *= half(0.95 + 0.05 * fbm(q * 1.6 + 3.0, 3));
    half alpha = half(density);
    return half4(lit * alpha, alpha);
}
