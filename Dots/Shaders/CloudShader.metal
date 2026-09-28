#include <metal_stdlib>
#include "Noise.h"
using namespace metal;

/// The welcome's clouds: a bank that comes down from the top and almost fills the screen, foggy at
/// the edges, with see-through gaps and solid white in the middle, in up to three layers of depth.
/// Drawn by CloudsView (Onboarding/CloudsView.swift) into a Metal layer that can be smaller than the
/// screen and stretched up; every knob, the cost ones included, comes from CloudUniforms.
struct CloudUniforms {
    float width, height;        // view size in points
    float time;                 // seconds, for the drift
    float descend, leave, fade; // 0→1 as the bank comes down, as it lifts away; opacity
    float seed;
    float scale;                // cloud size (higher is smaller)
    float holes;                // how much is gaps (higher is more)
    float softness, travel, reach, edgeFog, drift, veil;
    // Cost: how many layers, and noise passes (octaves) for each part; 0 turns a part off.
    float layers, shapeOctaves, warpPasses, puffOctaves, shadeOctaves, wispOctaves, edgeOctaves;
};

/// fbm/billow with a run-time octave count, 0 giving the midpoint (no detail).
static inline float fbmN(float2 p, int octaves) { return octaves > 0 ? fbm(p, octaves) : 0.5; }
static inline float billowN(float2 p, int octaves) { return octaves > 0 ? billow(p, octaves) : 0.5; }

/// One layer: puffy, warped noise cut into clouds, lit from above, below a ragged front coming down
/// the screen. `depth` is 0 far … 1 near: far layers are finer, greyer, thinner and slower; near ones
/// are big bright billows that travel furthest. Returns premultiplied colour and coverage.
static half4 cloudLayer(float2 uv, float aspect, float depth, constant CloudUniforms &u) {
    float layerSeed = u.seed + depth * 17.3;
    float layerScale = u.scale * mix(2.2, 0.75, depth);
    // The far layer is small and hazy: one pass less of everything.
    int less = depth < 0.25 ? 1 : 0;
    // Near layers come down from further up, so the bank separates into depth as it falls.
    float fall = (1.0 - u.descend) * u.travel * mix(0.5, 1.4, depth) + u.leave * u.travel * mix(0.6, 1.6, depth);
    float2 q = uv + float2(-u.time * u.drift * mix(0.4, 1.0, depth), fall);
    float2 p = q * layerScale + layerSeed;

    // Warp: 0 none, 1 one pass (a single noise per axis), 2 the full fbm per axis.
    int warpPasses = int(u.warpPasses + 0.5);
    float2 warp = 0.0;
    if (warpPasses == 1) {
        warp = float2(noise(p * 0.5 + float2(0.0, u.time * 0.01)), noise(p * 0.5 + float2(5.2, 1.3))) - 0.5;
    } else if (warpPasses >= 2) {
        warp = float2(fbm(p * 0.5 + float2(0.0, u.time * 0.01), 3), fbm(p * 0.5 + float2(5.2, 1.3), 3)) - 0.5;
    }
    float2 w = p + warp * 0.9;
    int shape = max(1, int(u.shapeOctaves + 0.5) - less);
    float n = fbm(w, shape) + (billowN(w * 2.3, max(0, int(u.puffOctaves + 0.5) - less)) - 0.5) * 0.22;
    // The same cloud a little higher up gives shaded undersides; off, the clouds are flat-lit.
    int shade = max(0, int(u.shadeOctaves + 0.5) - less);
    float above = shade > 0 ? fbm(w - float2(0.0, 0.12), shade) : n;

    // The bank's ragged front, a little lower for near layers; everything above it is cloud.
    float front = u.descend * (1.0 - u.leave) * u.reach * mix(0.85, 1.05, depth);
    float ragged = (fbmN(float2(uv.x * 2.2, u.time * 0.05) + layerSeed, int(u.edgeOctaves + 0.5)) - 0.5) * 0.35;
    float inBank = 1.0 - smoothstep(front - 0.12, front + 0.14, uv.y + ragged);

    // Thicker toward the screen's edges, so the middle keeps its gaps.
    float2 centered = float2((uv.x - aspect * 0.5) / aspect, uv.y - 0.5) * 2.0;
    float edge = smoothstep(0.35, 1.05, length(centered * float2(1.0, 0.8)));

    float body = n + edge * u.edgeFog * 0.25 - (1.0 - inBank) * 0.7 - u.leave * 0.35;
    float cover = u.holes + (1.0 - depth) * 0.06; // far layers a touch thinner
    float density = smoothstep(cover, cover + u.softness, body);
    // Wisps: fine noise frays the soft edges without touching the solid white.
    int wisps = max(0, int(u.wispOctaves + 0.5) - less);
    if (wisps > 0) {
        density *= mix(smoothstep(0.2, 0.6, fbm(w * 3.1, wisps)), 1.0, smoothstep(0.3, 0.7, density));
    }
    // A thin fog in the bank, heavier at the edges.
    float fog = inBank * mix(0.05, 0.35, edge) * u.edgeFog;
    float alpha = clamp(max(density, fog * (1.0 - depth * 0.5)), 0.0, 1.0) * mix(0.55, 1.0, depth);

    // Lit from above: bright tops, cool grey undersides, far layers hazier and bluer.
    float lit = clamp(0.7 + (n - above) * 2.5 + density * 0.3, 0.0, 1.0);
    half3 shadow = mix(half3(0.80h, 0.83h, 0.89h), half3(0.86h, 0.88h, 0.92h), half(depth));
    half3 colour = mix(shadow, half3(1.0h), half(lit));
    colour = mix(half3(0.90h, 0.92h, 0.96h), colour, half(mix(0.6, 1.0, depth)));
    return half4(colour * half(alpha), half(alpha));
}

struct CloudVertex {
    float4 position [[position]];
    float2 uv; // 0…1 across and down the view
};

/// One triangle that covers the whole view.
vertex CloudVertex cloudVertex(uint id [[vertex_id]]) {
    float2 corner = float2((id << 1) & 2, id & 2);
    CloudVertex out;
    out.position = float4(corner * float2(2.0, -2.0) + float2(-1.0, 1.0), 0.0, 1.0);
    out.uv = corner;
    return out;
}

fragment half4 cloudFragment(CloudVertex in [[stage_in]], constant CloudUniforms &u [[buffer(0)]]) {
    float aspect = u.width / u.height;
    float2 uv = float2(in.uv.x * aspect, in.uv.y); // screen height = 1, y down

    // Layers back to front; with fewer than three, the nearest ones are kept.
    int layers = clamp(int(u.layers + 0.5), 1, 3);
    half4 result = half4(0.0h);
    for (int i = 3 - layers; i < 3; i++) {
        half4 layer = cloudLayer(uv, aspect, float(i) / 2.0, u);
        result = layer + result * (1.0h - layer.a);
    }

    // The veil: soft white around the dots and text, only once the clouds are there.
    float2 d = float2(uv.x - aspect * 0.5, uv.y - 0.5);
    half v = half(u.veil * exp(-dot(d, d) * 5.0) * u.descend * (1.0 - u.leave));
    result = half4(v) + result * (1.0h - v);
    return result * half(u.fade);
}
