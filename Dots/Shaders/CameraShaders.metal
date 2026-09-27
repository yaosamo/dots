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
