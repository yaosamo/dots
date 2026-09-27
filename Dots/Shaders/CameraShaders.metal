#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
#include "Noise.h"
using namespace metal;

/// Fire around the camera bubble (see EffectRim in Camera/CameraView.swift). The layer is the
/// bubble's outline as a white stroke; flames grow off it outward and upward, so the top licks
/// straight up, the sides lick out and up, and the bottom gives a shorter glow. Each pixel searches
/// back along its flame's direction for the stroke, continuously (the steps are jittered per pixel,
/// so there are no bands), with each tongue's height and sway shaped by drifting noise.
/// SwiftUI's y axis grows downward.
///
/// - center: the bubble's center in the layer. height: the tallest flames, in points.
/// - speed: how fast the noise rises. wobble: how far the flames sway sideways.
[[ stitchable ]] half4 rimFire(float2 position, SwiftUI::Layer layer, float time, float2 center,
                               float height, float speed, float wobble) {
    float2 fromCenter = position - center;
    float2 outward = fromCenter / max(length(fromCenter), 1.0);
    // Flames go outward, bent upward; the bottom's point down, so they're kept short.
    float2 rawDirection = outward * 0.8 + float2(0.0, -0.55);
    float2 direction = normalize(rawDirection + float2(0.0, -0.001));
    float upness = clamp(-direction.y * 0.5 + 0.5, 0.0, 1.0);
    float2 across = float2(-direction.y, direction.x);

    // Noise that rises with the flames: where the tongues are, and how they sway.
    float along = dot(position, across);
    float rise = dot(position, direction);
    // Wide, uneven tongues: some tall, some barely there.
    float tongues = smoothstep(0.3, 0.72, fbm(float2(along * 0.022, time * speed * 0.8 - rise * 0.01), 4));
    float reach = height * mix(0.45, 1.0, upness) * (0.25 + 1.2 * tongues);

    // Search back toward the stroke; a per-pixel offset hides the steps.
    const int taps = 12;
    float jitter = hash(position * 0.37 + 11.0);
    half heat = 0.0h;
    for (int k = 0; k < taps; k++) {
        float d = (float(k) + jitter) / float(taps) * reach;
        float sway = (fbm(float2(along * 0.05 + d * 0.02, time * speed * 1.7 - d * 0.045), 3) - 0.5) * wobble;
        // Sway grows toward the tips, so the base stays on the bubble's edge.
        float2 sample = position - direction * d + across * sway * (d / max(reach, 1.0));
        float falloff = pow(max(1.0 - d / max(reach, 1.0), 0.0), 0.85);
        heat = max(heat, layer.sample(sample).a * half(falloff));
    }
    // Flicker inside the flames.
    float flicker = fbm(float2(along * 0.09, rise * 0.09 + time * speed * 2.6), 3);
    half h = clamp(heat * half(0.7 + 0.6 * flicker), 0.0h, 1.0h);
    h = max(h, layer.sample(position).a * 0.82h); // the base

    // Deep red at the tips, through orange and yellow, to near white at the base.
    half3 color = mix(half3(0.55h, 0.05h, 0.0h), half3(1.0h, 0.35h, 0.02h), smoothstep(0.05h, 0.35h, h));
    color = mix(color, half3(1.0h, 0.78h, 0.2h), smoothstep(0.35h, 0.7h, h));
    color = mix(color, half3(1.0h, 0.97h, 0.85h), smoothstep(0.75h, 1.0h, h));
    half alpha = smoothstep(0.04h, 0.3h, h);
    return half4(color * alpha, alpha);
}
