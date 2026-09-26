import SwiftUI

/// Onlook's header background, ported: a dark gradient slowly marbled by noise, with ink that
/// trails the pointer. Feed it the pointer from the view on top (so hovering the dots or text still
/// draws), e.g. `.onContinuousHover { trail.track($0) }` on the welcome's ZStack.
struct FlowBackground: View {
    let trail: PointerTrail
    var style = FlowStyle.onlook
    var fade: Double = 1

    @State private var startDate = Date()

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { timeline in
                let size = proxy.size
                let number: (Double) -> Shader.Argument = { .float(Float($0)) }
                let color: (FlowStyle.RGB) -> Shader.Argument = { .float3(Float($0.r), Float($0.g), Float($0.b)) }
                Rectangle()
                    .fill(.black)
                    .colorEffect(ShaderLibrary.welcomeFlow(
                        .float2(size),
                        number(timeline.date.timeIntervalSince(startDate)),
                        .floatArray(trail.values(at: timeline.date, in: size, life: style.life)),
                        color(style.top), color(style.middle), color(style.bottom), number(style.angle),
                        color(style.accent), number(style.accentMix),
                        number(style.brush), number(style.sharpness), number(style.inkSpeed),
                        number(style.intensity), number(style.life), number(style.spread),
                        number(style.advect), number(style.liquify),
                        number(style.warp), number(style.warpScale), number(style.flow),
                        number(style.paint), number(fade)
                    ))
            }
        }
        .ignoresSafeArea()
    }
}

/// The pointer's recent path, for `FlowBackground`'s ink. Not observed: the background redraws
/// every frame anyway and reads it then.
@MainActor
final class PointerTrail {
    private struct Sample {
        var point: CGPoint
        var date: Date
    }

    /// Enough for the ink's life at 60–120 Hz; each sample costs every pixel a little.
    private static let capacity = 64
    private var samples: [Sample] = []

    func track(_ phase: HoverPhase) {
        guard case .active(let point) = phase else { return }
        let now = Date()
        // About a frame apart, and only when it moved: resting adds nothing, like theirs.
        if let last = samples.last,
           now.timeIntervalSince(last.date) < 1.0 / 90 || hypot(point.x - last.point.x, point.y - last.point.y) < 1 {
            return
        }
        samples.append(Sample(point: point, date: now))
        if samples.count > Self.capacity { samples.removeFirst(samples.count - Self.capacity) }
    }

    /// (x, y, age) for each sample still showing, oldest first, x and y 0…1 across and up.
    func values(at date: Date, in size: CGSize, life: Double) -> [Float] {
        let cutoff = life * 3 // under 5% left by then
        samples.removeAll { date.timeIntervalSince($0.date) > cutoff }
        guard size.width > 0, size.height > 0 else { return [] }
        return samples.flatMap { sample in
            [Float(sample.point.x / size.width), Float(1 - sample.point.y / size.height),
             Float(max(0, date.timeIntervalSince(sample.date)))]
        }
    }
}

/// `FlowBackground`'s look; see `welcomeFlow` in Shaders/FlowShader.metal for what each knob does.
struct FlowStyle {
    struct RGB {
        var r, g, b: Double
    }

    var top: RGB
    var middle: RGB
    var bottom: RGB
    var angle: Double
    var accent: RGB
    var accentMix: Double
    var brush: Double
    var sharpness: Double
    var inkSpeed: Double
    var intensity: Double
    var life: Double
    var spread: Double
    var advect: Double
    var liquify: Double
    var warp: Double
    var warpScale: Double
    var flow: Double
    var paint: Double

    /// Onlook's scene values: #151515 fading to black, and ink half rainbow, half #F50032.
    static let onlook = FlowStyle(
        top: RGB(r: 0.082, g: 0.082, b: 0.082), middle: RGB(r: 0, g: 0, b: 0), bottom: RGB(r: 0, g: 0, b: 0),
        angle: 0.0783,
        accent: RGB(r: 0.961, g: 0, b: 0.196), accentMix: 0.5,
        brush: 0.1, sharpness: 3, inkSpeed: 1.2, intensity: 2.5,
        life: 0.5, spread: 1.2, advect: 0.35, liquify: 0.02,
        warp: 1, warpScale: 0.15, flow: 1, paint: 0
    )

    /// For the welcome's light look: a pale sky with the ink laid on as soft paint.
    static let light = FlowStyle(
        top: RGB(r: 0.9, g: 0.91, b: 0.94), middle: RGB(r: 0.96, g: 0.965, b: 0.975), bottom: RGB(r: 0.99, g: 0.99, b: 1),
        angle: 0.0783,
        accent: RGB(r: 0.35, g: 0.45, b: 1), accentMix: 0.4,
        brush: 0.1, sharpness: 3, inkSpeed: 1.2, intensity: 0.9,
        life: 0.6, spread: 1.2, advect: 0.35, liquify: 0.02,
        warp: 1, warpScale: 0.15, flow: 1, paint: 1
    )
}

#Preview("Onlook") {
    let trail = PointerTrail()
    return FlowBackground(trail: trail)
        .onContinuousHover { trail.track($0) }
        .frame(width: 900, height: 560)
}

#Preview("Light") {
    let trail = PointerTrail()
    return FlowBackground(trail: trail, style: .light)
        .onContinuousHover { trail.track($0) }
        .frame(width: 900, height: 560)
}
