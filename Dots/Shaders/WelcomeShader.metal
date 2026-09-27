#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
#include "Noise.h"
using namespace metal;

/// The welcome's storm: fractal clouds swirl into the middle of the screen while darkness closes
/// in from the edges toward the center, with lightning in the clouds, until a bloom bursts from the
/// center and sweeps the darkness away, leaving a bright sky with the clouds blown out to the sides.
/// Driven entirely by its arguments (see StormFrame in Onboarding/Welcome.swift and the knobs in
/// Onboarding/WelcomeTuning.swift).
///
/// - size: view size in points. time: seconds, for drift and swirl.
/// - gather: 0→1 as the clouds pull into the middle and knot up, and the darkness closes in.
/// - bloom: 0→1 as the bloom's edge sweeps from the center past the screen's corners.
/// - burst: 0→1 as the clouds are pushed out sideways, clearing the middle; more while leaving.
/// - flash: lightning brightness. flashPoint: where it strikes, 0…1 across and down the screen.
///   strikeSeed: varies each bolt's shape.
/// - fade: overall opacity. seed: varies the clouds between openings.
/// - cloudScale, cloudCover (lower is cloudier), swirl, drift: the clouds.
/// - darkSoftness: the closing darkness's edge. darkest: the sky's darkest grey.
/// - lightning: 0 none, 1 glow behind the clouds, 2 forked bolts, 3 sheet lightning.
/// - bloomRim: the bloom edge's brightness. bloomPop: the flash as it bursts.
[[ stitchable ]] half4 welcomeStorm(float2 position, half4 color, float2 size, float time,
                                    float gather, float bloom, float burst, float flash,
                                    float2 flashPoint, float strikeSeed, float fade, float seed,
                                    float cloudScale, float cloudCover, float swirl, float drift,
                                    float darkSoftness, float darkest, float lightning,
                                    float bloomRim, float bloomPop) {
    float aspect = size.x / size.y;
    float2 uv = position / size.y; // screen height = 1
    float2 center = float2(aspect * 0.5, 0.5);
    float2 d = uv - center;
    float dist = length(d);

    // Blow apart: sample nearer the middle, so clouds appear pushed out (mostly sideways).
    float2 q = d / float2(1.0 + burst * 2.6, 1.0 + burst * 0.35);
    // Gather: sample farther out, so clouds drift in, and swirl them around the middle.
    q *= 1.0 + gather * 0.9;
    float r = length(q);
    float angle = gather * swirl / (1.0 + r * 5.0) + time * 0.1 * gather;
    float s = sin(angle), c = cos(angle);
    q = float2(c * q.x - s * q.y, s * q.x + c * q.y);

    float2 p = q * cloudScale + seed + float2(time * drift, time * drift * 0.4);
    float n = fbm(p, 5);
    float shade = fbm(p * 1.8 + 7.3, 3);

    // Clouds knot up in the middle as they gather; the blast clears a widening corridor.
    float core = exp(-dot(d, d) * 9.0) * gather;
    float density = smoothstep(cloudCover, cloudCover + 0.34, n + core * 0.45);
    float corridor = smoothstep(burst * 0.3, burst * 0.3 + 0.25, abs(d.x));
    float cleared = density * mix(1.0, corridor, clamp(burst * 1.5, 0.0, 1.0));

    // The storm: greys that sink toward night, the dark closing in from the edges as it gathers.
    // Its front starts past the corners and shrinks to the center; outside it, it's night.
    float corner = length(float2(aspect * 0.5, 0.5));
    float front = (1.0 - gather) * (corner + darkSoftness);
    half darkness = half(smoothstep(front - darkSoftness, front + 0.05, dist));
    half3 night = half3(half(darkest), half(darkest * 1.1), half(darkest * 1.45));
    half3 stormSky = mix(half3(0.42h, 0.44h, 0.48h), night, darkness);
    half3 stormLow = mix(half3(0.3h, 0.32h, 0.36h), night * 0.5h, min(half(1.0), darkness + half(core) * 0.5h));
    half3 stormHigh = mix(half3(0.62h, 0.64h, 0.68h), night + half3(0.12h), darkness);
    half3 stormCloud = mix(stormLow, stormHigh, half(smoothstep(0.3, 0.75, shade)));
    half3 storm = mix(stormSky, stormCloud, half(density));

    // Lightning.
    float2 strike = float2(flashPoint.x * aspect, flashPoint.y);
    int style = int(lightning + 0.5);
    if (style == 1) {
        // A cold glow behind the clouds: shows through thin cloud and rims the thick.
        float glow = flash * exp(-dot(uv - strike, uv - strike) * 12.0);
        storm += half3(0.72h, 0.8h, 1.0h) * half(glow * (1.2 - density * 0.6));
    } else if (style == 2) {
        // A jagged bolt from above down to the strike, with a halo, half hidden by thick cloud.
        float top = strike.y - 0.5;
        float bolt = 0.0;
        if (uv.y > top && uv.y < strike.y) {
            float along = (uv.y - top) / (strike.y - top);
            float jag = (noise(float2(uv.y * 14.0, strikeSeed)) - 0.5) * 0.14
                      + (noise(float2(uv.y * 48.0, strikeSeed + 3.0)) - 0.5) * 0.035;
            float dx = abs(uv.x - (strike.x + jag * (0.4 + along)));
            // The halo fades out at both ends, so it doesn't stop on a hard line.
            float ends = smoothstep(0.0, 0.12, along) * (1.0 - smoothstep(0.8, 1.0, along));
            bolt = exp(-dx * 700.0) + exp(-dx * 50.0) * 0.3 * ends;
        }
        float glow = exp(-dot(uv - strike, uv - strike) * 30.0) * 0.6;
        storm += half3(0.82h, 0.88h, 1.0h) * half(flash * (bolt + glow) * (1.1 - density * 0.5));
    } else if (style == 3) {
        // Sheet lightning: the whole sky lights up from within, the thin cloud most.
        storm += half3(0.55h, 0.62h, 0.8h) * half(flash * (0.3 + (1.0 - density) * 0.45));
    }
    if (style > 0) { storm += half(flash * 0.05); } // the whole sky blinks a little

    // After the bloom: a pale sky, the clouds white and blown out to the sides.
    half3 lightSky = half3(0.94h, 0.95h, 0.97h);
    half3 lightCloud = mix(half3(0.8h, 0.82h, 0.86h), half3(1.0h), half(smoothstep(0.3, 0.75, shade)));
    half3 light = mix(lightSky, lightCloud, half(cleared * 0.85));

    // The bloom: a disc of light racing out from the center, with a hot rim at its edge.
    float reach = bloom * (aspect * 0.75 + 0.3);
    float inside = smoothstep(reach + 0.06, reach - 0.06, dist);
    half3 col = mix(storm, light, half(inside));
    float started = step(0.001, bloom);
    float rim = exp(-pow((dist - reach) / 0.07, 2.0)) * (1.0 - bloom) * started;
    col += half(rim * bloomRim);
    col += half((1.0 - smoothstep(0.0, 0.25, bloom)) * started * bloomPop); // the pop
    col = min(col, half3(1.0h));
    return half4(col * half(fade), half(fade));
}
