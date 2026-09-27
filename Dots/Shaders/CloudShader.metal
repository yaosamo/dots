#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
#include "Noise.h"
using namespace metal;

/// One layer of the welcome's cloud bank: puffy, domain-warped noise cut into clouds, lit from
/// above, below a ragged front that comes down the screen. `depth` is 0 far … 1 near: far layers
/// are finer, greyer, thinner and slower; near ones are big bright billows that travel furthest.
/// Returns premultiplied white-ish colour and coverage.
static half4 cloudLayer(float2 uv, float aspect, float depth, float time, float descend, float leave,
                        float seed, float scale, float holes, float softness, float travel,
                        float reach, float edgeFog, float drift) {
    float layerSeed = seed + depth * 17.3;
    float layerScale = scale * mix(2.2, 0.75, depth);
    // Near layers come down from further up, so the bank separates into depth as it falls.
    float fall = (1.0 - descend) * travel * mix(0.5, 1.4, depth) + leave * travel * mix(0.6, 1.6, depth);
    float2 q = uv + float2(-time * drift * mix(0.4, 1.0, depth), fall);

    // Gently warped fbm for the shapes, with billowy detail (folded noise) for the puffy edges.
    float2 p = q * layerScale + layerSeed;
    float2 warp = float2(fbm(p * 0.5 + float2(0.0, time * 0.01), 3), fbm(p * 0.5 + float2(5.2, 1.3), 3)) - 0.5;
    float2 w = p + warp * 0.9;
    float n = fbm(w, 4) + (billow(w * 2.3, 3) - 0.5) * 0.22;
    // The same cloud a little higher up: shaded undersides where there's cloud above them.
    float above = fbm(w - float2(0.0, 0.12), 4);

    // The bank's ragged front, a little lower for near layers; everything above it is cloud.
    float front = descend * (1.0 - leave) * reach * mix(0.85, 1.05, depth);
    float ragged = (fbm(float2(uv.x * 2.2, time * 0.05) + layerSeed, 3) - 0.5) * 0.35;
    float inBank = 1.0 - smoothstep(front - 0.12, front + 0.14, uv.y + ragged);

    // Thicker toward the screen's edges, so the middle keeps its gaps.
    float2 centered = float2((uv.x - aspect * 0.5) / aspect, uv.y - 0.5) * 2.0;
    float edge = smoothstep(0.35, 1.05, length(centered * float2(1.0, 0.8)));

    float body = n + edge * edgeFog * 0.25 - (1.0 - inBank) * 0.7 - leave * 0.35;
    float cover = holes + (1.0 - depth) * 0.06; // far layers a touch thinner
    float density = smoothstep(cover, cover + softness, body);
    // Wisps: fine noise frays the soft edges without touching the solid white.
    float wisps = fbm(w * 3.1, 3);
    density *= mix(smoothstep(0.2, 0.6, wisps), 1.0, smoothstep(0.3, 0.7, density));
    // A thin fog in the bank, heavier at the edges.
    float fog = inBank * mix(0.05, 0.35, edge) * edgeFog;
    float alpha = clamp(max(density, fog * (1.0 - depth * 0.5)), 0.0, 1.0) * mix(0.55, 1.0, depth);

    // Lit from above: bright tops, cool grey undersides, far layers hazier and bluer.
    float lit = clamp(0.7 + (n - above) * 2.5 + density * 0.3, 0.0, 1.0);
    half3 shadow = mix(half3(0.80h, 0.83h, 0.89h), half3(0.86h, 0.88h, 0.92h), half(depth));
    half3 colour = mix(shadow, half3(1.0h), half(lit));
    colour = mix(half3(0.90h, 0.92h, 0.96h), colour, half(mix(0.6, 1.0, depth)));
    return half4(colour * half(alpha), half(alpha));
}

/// The welcome's clouds: a bank that comes down from the top and almost fills the screen, foggy at
/// the edges, with see-through gaps and solid white in the middle, in three layers of depth.
/// Driven entirely by its arguments (see CloudFrame in Onboarding/Welcome.swift and the Clouds
/// knobs in Onboarding/WelcomeTuning.swift).
///
/// - size: view size in points. time: seconds, for the drift.
/// - descend: 0→1 as the bank comes down. leave: 0→1 as it lifts and thins away. fade: opacity.
/// - seed: varies the clouds between openings.
/// - scale: cloud size (higher is smaller). holes: how much is gaps (higher is more).
/// - softness: cloud edges' softness. travel: how far the layers fall, for the depth.
/// - reach: how far down the bank ends up, in screen heights. edgeFog: fog at the screen's edges.
/// - drift: sideways speed. veil: a faint white behind the middle, to keep the text readable.
[[ stitchable ]] half4 welcomeClouds(float2 position, half4 color, float2 size, float time,
                                     float descend, float leave, float fade, float seed,
                                     float scale, float holes, float softness, float travel,
                                     float reach, float edgeFog, float drift, float veil) {
    float aspect = size.x / size.y;
    float2 uv = position / size.y; // screen height = 1, y down

    half4 result = half4(0.0h);
    for (int i = 0; i < 3; i++) {
        float depth = float(i) / 2.0;
        half4 layer = cloudLayer(uv, aspect, depth, time, descend, leave, seed, scale, holes, softness,
                                 travel, reach, edgeFog, drift);
        result = layer + result * (1.0h - layer.a); // back to front
    }

    // The veil: soft white around the dots and text, only once the clouds are there.
    float2 d = float2(uv.x - aspect * 0.5, uv.y - 0.5);
    half v = half(veil * exp(-dot(d, d) * 5.0) * descend * (1.0 - leave));
    result = half4(v) + result * (1.0h - v);
    return result * half(fade);
}
