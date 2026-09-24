#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
#include "Noise.h"
using namespace metal;

/// Alpha mask for the Tasks frost. Each pixel gets a "key" from fractal noise (mixed with a little
/// edge → centre bias); the pixel frosts as `progress` passes its key, with a soft threshold.
/// So the screen frosts unevenly: low-noise patches frost first and grow into the rest.
///
/// - size: view size in points.
/// - progress: 0 = clear, 1 = fully frosted.
/// - edgeBias: 0 = pure noise, 1 = pure edge → centre sweep.
/// - recede: 1 while closing, so edges also clear first on the way out.
/// - seed: shifts the noise so every opening looks different.
/// - scale: blotch size in points; octaves: fractal detail; soft: width of each patch's fade-in.
[[ stitchable ]] half4 frostMask(float2 position, half4 color, float2 size, float progress,
                                 float edgeBias, float recede, float seed,
                                 float scale, float octaves, float soft) {
    // Cloudy blotches with finer fractal detail from the higher octaves.
    float n = fbm(position / scale + seed, int(clamp(octaves, 1.0, 8.0)));
    n = clamp((n - 0.18) / 0.64, 0.0, 1.0); // stretch fbm's narrow range for more contrast

    // 0 at the centre, 1 at the corners, matching the screen's aspect.
    float d = clamp(length((position / size - 0.5) * 2.0) / sqrt(2.0), 0.0, 1.0);
    // Opening frosts where the key is low first; closing clears where it's high first.
    // Either way the edges lead.
    float edge = recede > 0.5 ? d : 1.0 - d;
    float key = mix(n, edge, edgeBias);

    float threshold = progress * (1.0 + 2.0 * soft) - soft; // spans every key softly
    half alpha = half(smoothstep(key - soft, key + soft, threshold));
    return half4(0.0h, 0.0h, 0.0h, 1.0h) * alpha;
}
