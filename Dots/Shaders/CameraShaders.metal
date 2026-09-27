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

/// A cloud the camera bubble sits in (see CloudRim in Camera/CameraView.swift): one soft, low mass
/// along the bubble's bottom edge, wider than the bubble so its corners are always buried, with a few
/// broad bumps melted into its top. Large-scale noise shapes the outline, so it's irregular rather
/// than scalloped, and drifting wisps thin the edges in and out, so they keep dissolving and
/// re-forming while the middle stays solid. Tops bright, underside soft grey-blue.
/// SwiftUI's y axis grows downward.
///
/// - size: this layer (the bubble's width plus `side` each side; a little above its bottom plus `below`).
/// - bubble: the bubble's size. side, below: how far the cloud spills out. time: for the motion.
[[ stitchable ]] half4 cameraCloud(float2 position, half4 color, float2 size, float2 bubble,
                                   float side, float below, float time) {
    float2 at = float2(position.x - size.x * 0.5, position.y - (size.y - below)); // 0 at the bubble's bottom middle
    float w = bubble.x; // sized from the width, so a tall bubble doesn't get a giant cloud
    float span = w * 0.5 + side * 0.5;
    // Big bubbles have less room below (the window's margin) than their cloud would hang: squash it
    // vertically to fit rather than cut it off.
    float squash = min(1.0, below / (w * 0.27));
    float2 p = float2(at.x, at.y / squash);

    // The mass: a wide, low ellipse around the bubble's bottom edge…
    float2 radii = float2(span, w * 0.15);
    float d = (length((p - float2(0.0, w * 0.03)) / radii) - 1.0) * radii.y;
    // …with a few broad bumps melted into its top (heavily blended, so no circles show), two of them
    // right over the bubble's bottom corners, so a rectangle's corners stay buried.
    float corner = w * 0.47 / span;
    const float3 bumps[5] = { float3(-0.45, -0.07, 0.15), float3(0.06, -0.09, 0.18), float3(0.5, -0.06, 0.14),
                              float3(-1.0, -0.03, 0.13), float3(1.0, -0.03, 0.13) };
    float k = w * 0.12;
    for (int i = 0; i < 5; i++) {
        float breathe = 1.0 + 0.05 * sin(time * 0.8 + float(i) * 2.1);
        float x = i < 3 ? bumps[i].x * span : bumps[i].x * corner * span;
        float2 center = float2(x + sin(time * 0.3 + float(i)) * w * 0.015, bumps[i].y * w);
        float bump = length(p - center) - bumps[i].z * w * breathe;
        float blend = clamp(0.5 + 0.5 * (bump - d) / k, 0.0, 1.0);
        d = mix(bump, d, blend) - k * blend * (1.0 - blend);
    }

    // An irregular, natural outline from large-scale noise, slowly shifting.
    float drift = time * 0.12;
    float2 q = p / w;
    float2 warp = float2(fbm(q * 3.0 + float2(drift, 1.3), 3), fbm(q * 3.0 + float2(4.1, drift * 0.7), 3)) - 0.5;
    d += (fbm(q * 4.0 + warp * 0.8 + float2(drift * 0.6, 0.0), 4) - 0.5) * w * 0.12;

    // Solid inside, with a wide soft margin where drifting wisps thin the edge in and out.
    float edge = smoothstep(-w * 0.1, w * 0.04, d);       // 0 in the core, 1 at the outline
    float wisps = fbm(q * 9.0 + warp * 1.5 + float2(drift * 1.8, -drift), 4);
    float density = (1.0 - smoothstep(-w * 0.03, w * 0.05, d)) * mix(1.0, smoothstep(0.28, 0.72, wisps), edge);
    // Fade out before the layer's edges, so no wisp is ever cut off square.
    density *= 1.0 - smoothstep(size.x * 0.5 - side * 0.45, size.x * 0.5 - 2.0, abs(at.x));
    density *= 1.0 - smoothstep(below * 0.7, below - 1.0, at.y);
    density *= smoothstep(1.0, size.y * 0.12, position.y);

    // Bright on top, soft grey-blue underneath, with a hint of texture.
    float lower = clamp((p.y + w * 0.12) / (w * 0.3), 0.0, 1.0);
    half3 lit = mix(half3(1.0h), half3(0.84h, 0.87h, 0.93h), half(smoothstep(0.2, 1.0, lower)));
    lit *= half(0.95 + 0.05 * wisps);
    half alpha = half(clamp(density, 0.0, 1.0));
    return half4(lit * alpha, alpha);
}
