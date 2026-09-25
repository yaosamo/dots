#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
#include "Noise.h"
using namespace metal;

/// The welcome's storm: white fractal clouds that swirl into a dark knot in the middle of the
/// screen, light up from behind with lightning, then blow apart to the left and right.
/// Driven entirely by its arguments (see StormFrame in Onboarding/Welcome.swift).
///
/// - size: view size in points. time: seconds, for drift and swirl.
/// - gather: 0→1 as the clouds pull into the middle and knot up.
/// - burst: 0→1 as the blast pushes them out sideways and clears the middle; more while leaving.
/// - flash: lightning brightness. flashPoint: where it strikes, 0…1 across and down the screen.
/// - fade: overall opacity. seed: varies the clouds between openings.
[[ stitchable ]] half4 welcomeStorm(float2 position, half4 color, float2 size, float time,
                                    float gather, float burst, float flash, float2 flashPoint,
                                    float fade, float seed) {
    float aspect = size.x / size.y;
    float2 uv = position / size.y; // screen height = 1
    float2 center = float2(aspect * 0.5, 0.5);
    float2 d = uv - center;

    // Blow apart: sample nearer the middle, so clouds appear pushed out (mostly sideways).
    float2 q = d / float2(1.0 + burst * 2.6, 1.0 + burst * 0.35);
    // Gather: sample farther out, so clouds drift in, and swirl them around the middle.
    q *= 1.0 + gather * 0.9;
    float r = length(q);
    float angle = gather * 2.2 / (1.0 + r * 5.0) + time * 0.12 * gather;
    float s = sin(angle), c = cos(angle);
    q = float2(c * q.x - s * q.y, s * q.x + c * q.y);

    float2 p = q * 2.6 + seed + float2(time * 0.04, time * 0.015);
    float n = fbm(p, 5);

    // The storm's knot: dense and dark in the middle while it gathers.
    float core = exp(-dot(d, d) * 9.0) * gather * (1.0 - clamp(burst, 0.0, 1.0));
    float density = smoothstep(0.38, 0.72, n + core * 0.45);
    // The blast clears a corridor down the middle that widens as the clouds fly apart.
    float corridor = smoothstep(burst * 0.3, burst * 0.3 + 0.25, abs(d.x));
    density *= mix(1.0, corridor, clamp(burst * 1.5, 0.0, 1.0));

    // White theme: a pale sky, white cloud tops, grey undersides that darken in the knot.
    float shade = fbm(p * 1.8 + 7.3, 3);
    half3 sky = half3(0.93h, 0.94h, 0.96h);
    half3 underside = mix(half3(0.78h, 0.8h, 0.84h), half3(0.36h, 0.38h, 0.44h), half(core));
    half3 cloud = mix(underside, half3(1.0h), half(smoothstep(0.3, 0.75, shade)));
    half3 col = mix(sky, cloud, half(density));

    // Lightning behind the clouds: a cold glow that shows through thin cloud and rims the thick.
    float2 strike = float2(flashPoint.x * aspect, flashPoint.y);
    float glow = flash * exp(-dot(uv - strike, uv - strike) * 14.0);
    col += half3(0.8h, 0.87h, 1.0h) * half(glow * (1.1 - density * 0.5));
    col += half(flash * 0.06); // the whole sky blinks a little
    col = min(col, half3(1.0h));
    return half4(col * half(fade), half(fade));
}
