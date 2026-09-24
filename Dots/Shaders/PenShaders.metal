#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
#include "Noise.h"
using namespace metal;

// Brush shaders for the pen. Each stroke layer is drawn as a plain white mask, and these
// shaders turn its alpha into light. SwiftUI's y axis grows downward.
// `position` is local to the layer (use it to sample); `origin` is the layer's screen offset,
// so `position + origin` keeps noise and color fixed to the screen as the layer resizes.

/// Mean stroke coverage on a ring of 8 taps around `p` — a cheap glow.
static half ring(SwiftUI::Layer layer, float2 p, float radius) {
    half sum = 0.0h;
    for (int i = 0; i < 8; i++) {
        float angle = float(i) * M_PI_F / 4.0;
        sum += layer.sample(p + radius * float2(cos(angle), sin(angle))).a;
    }
    return sum / 8.0h;
}

/// Crackling arc: the stroke jitters in discrete ticks with a flickering blue corona.
[[ stitchable ]] half4 electric(float2 position, SwiftUI::Layer layer, float time, float2 origin,
                                float jitterAmount, float rate, float glowRadius) {
    float tick = floor(time * rate);
    float2 world = position + origin;
    float2 jitter = float2(noise(world * 0.06 + tick * 3.1),
                           noise(world * 0.06 + 17.0 + tick * 2.3)) - 0.5;
    float2 p = position + jitter * jitterAmount;
    half core = layer.sample(p).a;
    half glow = ring(layer, p, glowRadius * 0.44) * 0.6h + ring(layer, p, glowRadius) * 0.4h;
    half flicker = half(0.7 + 0.3 * hash(float2(tick, 1.0)));
    half alpha = clamp(core + glow * 1.2h * flicker, 0.0h, 1.0h);
    half3 color = half3(0.85h, 0.95h, 1.0h) * core + half3(0.25h, 0.6h, 1.0h) * glow * 1.6h * flicker;
    return half4(min(color, half3(alpha)), alpha);
}

/// Flames licking upward off the stroke: each pixel looks for stroke below it, warped by rising noise.
[[ stitchable ]] half4 fire(float2 position, SwiftUI::Layer layer, float time, float2 origin,
                            float height, float speed, float wobble) {
    float2 world = position + origin;
    float n = fbm(float2(world.x * 0.045, world.y * 0.045 + time * speed));
    float2 p = position + float2((n - 0.5) * wobble, 0.0);
    half heat = 0.0h;
    for (int k = 0; k < 7; k++) {
        half falloff = half(1.0 - float(k) / 7.0);
        heat = max(heat, layer.sample(p + float2(0.0, float(k) * height / 7.0)).a * falloff);
    }
    float turbulence = fbm(float2(world.x * 0.08, world.y * 0.08 + time * speed * 1.54));
    half h = clamp(heat * half(0.55 + 0.9 * turbulence), 0.0h, 1.0h);
    h = max(h, layer.sample(position).a * 0.9h);
    half3 color = half3(1.0h, smoothstep(0.25h, 0.9h, h) * 0.85h, smoothstep(0.7h, 1.0h, h) * 0.55h);
    half alpha = smoothstep(0.08h, 0.45h, h);
    return half4(color * alpha, alpha);
}

/// Hue sweeps diagonally across the screen and drifts over time.
[[ stitchable ]] half4 rainbow(float2 position, half4 color, float time, float2 origin,
                               float scale, float speed) {
    float2 world = position + origin;
    float hue = fract((world.x + world.y) * scale * 0.001 - time * speed);
    float3 rgb = clamp(abs(fmod(hue * 6.0 + float3(0.0, 4.0, 2.0), float3(6.0)) - 3.0) - 1.0, float3(0.0), float3(1.0));
    return half4(half3(rgb) * color.a, color.a);
}
