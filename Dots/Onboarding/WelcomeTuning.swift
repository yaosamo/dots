import Foundation

/// Every knob of the first-launch welcome, edited live in Welcome Lab (menu bar menu). Values
/// persist between launches. Welcome Lab's "Copy" produces a `Values(...)` literal; paste it over
/// the defaults below to make a tuning permanent.
@MainActor
final class WelcomeTuning: ObservableObject {
    struct Values: Codable, Equatable {
        // Timing, in seconds
        var dotBeat: Double = 0.35
        var dotEmerge: Double = 0.9
        /// After the last dot, before the text.
        var textDelay: Double = 0.7
        /// After the text, before the hint and Done.
        var hintDelay: Double = 0.8
        // Clouds (Shaders/CloudShader.metal)
        /// From opening until the clouds have come down (the first dot comes partway, see `cloudDotsAt`).
        var cloudDescend: Double = 1.636
        /// When the first dot comes, as a share of the clouds' coming down.
        var cloudDotsAt: Double = 0.5
        /// Once Done lands the dots, the clouds lift away over this.
        var cloudLeave: Double = 0.6
        /// In dot setup (+), how long after the clouds start coming down the dots and cards follow.
        var cloudSetupEnterDelay: Double = 0.2
        /// In dot setup (+), how long after the dots and cards start moving the clouds follow.
        var cloudSetupLeaveDelay: Double = 0.12
        /// Higher is smaller clouds.
        var cloudSize: Double = 2.762
        /// Higher is more see-through gaps.
        var cloudHoles: Double = 0.2
        var cloudSoftness: Double = 0.337
        /// How far the layers fall, apart from each other: the depth.
        var cloudDepth: Double = 0
        /// How far down the bank comes, in screen heights.
        var cloudReach: Double = 0.741
        var cloudEdgeFog: Double = 0.832
        var cloudDrift: Double = 0.025
        /// Faint white behind the dots and text, so the text reads over a dark desktop.
        var cloudVeil: Double = 0.878
        // Clouds' cost (see the readout in Welcome Lab)
        /// Of the screen's pixels, per side; the clouds are stretched up from there.
        var cloudResolution: Double = 0.33
        var cloudFPS: Double = 60
        var cloudLayers: Double = 3
        /// Noise passes (octaves) per part; 0 turns a part off. The far layer gets one less.
        var cloudShapeDetail: Double = 4
        /// 0 none, 1 cheap, 2 full.
        var cloudWarp: Double = 1
        var cloudPuffDetail: Double = 2
        var cloudShadeDetail: Double = 2
        var cloudWispDetail: Double = 2
        var cloudEdgeDetail: Double = 2
        // Dots, in points
        var dotSize: Double = 120
        var dotSpacing: Double = 168
        /// From the screen's middle; negative is up.
        var dotsOffsetY: Double = -10
        var dotBlur: Double = 18
        var dotStartScale: Double = 0.8
        // Text
        var message: String = "Hello, we’re dots - small and fun everyday tools for your computer"
        var hint: String = "Click a dot to see what it does"
        var textSize: Double = 24
        var hintSize: Double = 16
        var textWidth: Double = 560
        /// From the dots' bottom edge to the text's top.
        var textGap: Double = 30
        var textOpacity: Double = 0.85
    }

    static let shared = WelcomeTuning()
    /// Versioned: a new version drops saved tunings so changed defaults (the text) take effect.
    private static let defaultsKey = "welcomeTuning.2"

    @Published var values: Values {
        didSet { save() }
    }

    private init() {
        // A saved tuning from an older set of fields fails to decode; fall back to the defaults.
        values = UserDefaults.standard.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(Values.self, from: $0) } ?? Values()
    }

    func reset() {
        values = Values()
    }

    /// The current values as a Swift literal, ready to paste as new defaults.
    var swiftLiteral: String {
        let fields = Mirror(reflecting: values).children.compactMap { child -> String? in
            guard let label = child.label else { return nil }
            switch child.value {
            case let number as Double: return "    \(label): \(ShaderTuning.format(number))"
            case let text as String: return "    \(label): \(String(reflecting: text))"
            default: return nil
            }
        }
        return "WelcomeTuning.Values(\n" + fields.joined(separator: ",\n") + "\n)"
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}

/// One slider in Welcome Lab.
struct WelcomeParameter: Identifiable {
    let title: String
    let keyPath: WritableKeyPath<WelcomeTuning.Values, Double>
    let range: ClosedRange<Double>
    var step: Double?
    var unit = ""

    var id: String { title }
}

struct WelcomeSection: Identifiable {
    let title: String
    let parameters: [WelcomeParameter]

    var id: String { title }

    static let all: [WelcomeSection] = [
        WelcomeSection(title: "Timing", parameters: [
            WelcomeParameter(title: "Between dots", keyPath: \.dotBeat, range: 0...1.5, unit: "s"),
            WelcomeParameter(title: "Dot emerges over", keyPath: \.dotEmerge, range: 0.1...3, unit: "s"),
            WelcomeParameter(title: "Text after last dot", keyPath: \.textDelay, range: 0...3, unit: "s"),
            WelcomeParameter(title: "Hint and Done after text", keyPath: \.hintDelay, range: 0...3, unit: "s"),
        ]),
        WelcomeSection(title: "Clouds", parameters: [
            WelcomeParameter(title: "Come down over", keyPath: \.cloudDescend, range: 0.5...8, unit: "s"),
            WelcomeParameter(title: "First dot at (share of come down)", keyPath: \.cloudDotsAt, range: 0...1.5),
            WelcomeParameter(title: "Lift away over", keyPath: \.cloudLeave, range: 0.1...2, unit: "s"),
            WelcomeParameter(title: "Cards after clouds (+ menu)", keyPath: \.cloudSetupEnterDelay, range: 0...1.5, unit: "s"),
            WelcomeParameter(title: "Lift after dots (+ menu)", keyPath: \.cloudSetupLeaveDelay, range: 0...0.75, unit: "s"),
            WelcomeParameter(title: "Cloud size", keyPath: \.cloudSize, range: 0.3...5),
            WelcomeParameter(title: "Gaps", keyPath: \.cloudHoles, range: 0.2...0.8),
            WelcomeParameter(title: "Edge softness", keyPath: \.cloudSoftness, range: 0.02...0.6),
            WelcomeParameter(title: "Depth", keyPath: \.cloudDepth, range: 0...2),
            WelcomeParameter(title: "Reach", keyPath: \.cloudReach, range: 0.3...1.4),
            WelcomeParameter(title: "Edge fog", keyPath: \.cloudEdgeFog, range: 0...2),
            WelcomeParameter(title: "Drift speed", keyPath: \.cloudDrift, range: 0...0.1),
            WelcomeParameter(title: "Veil behind text", keyPath: \.cloudVeil, range: 0...1),
        ]),
        WelcomeSection(title: "Clouds · cost", parameters: [
            WelcomeParameter(title: "Resolution", keyPath: \.cloudResolution, range: 0.1...1, unit: "×"),
            WelcomeParameter(title: "Frame rate cap", keyPath: \.cloudFPS, range: 15...120, step: 15, unit: " fps"),
            WelcomeParameter(title: "Layers", keyPath: \.cloudLayers, range: 1...3, step: 1),
            WelcomeParameter(title: "Shape detail", keyPath: \.cloudShapeDetail, range: 1...6, step: 1),
            WelcomeParameter(title: "Warp (off, cheap, full)", keyPath: \.cloudWarp, range: 0...2, step: 1),
            WelcomeParameter(title: "Puff detail", keyPath: \.cloudPuffDetail, range: 0...4, step: 1),
            WelcomeParameter(title: "Shading detail", keyPath: \.cloudShadeDetail, range: 0...4, step: 1),
            WelcomeParameter(title: "Wisp detail", keyPath: \.cloudWispDetail, range: 0...4, step: 1),
            WelcomeParameter(title: "Front edge detail", keyPath: \.cloudEdgeDetail, range: 0...4, step: 1),
        ]),
        WelcomeSection(title: "Dots", parameters: [
            WelcomeParameter(title: "Size", keyPath: \.dotSize, range: 30...220, unit: "pt"),
            WelcomeParameter(title: "Spacing", keyPath: \.dotSpacing, range: 40...320, unit: "pt"),
            WelcomeParameter(title: "Vertical offset", keyPath: \.dotsOffsetY, range: -400...400, unit: "pt"),
            WelcomeParameter(title: "Start blur", keyPath: \.dotBlur, range: 0...60, unit: "pt"),
            WelcomeParameter(title: "Start scale", keyPath: \.dotStartScale, range: 0...1.5),
        ]),
        WelcomeSection(title: "Text", parameters: [
            WelcomeParameter(title: "Message size", keyPath: \.textSize, range: 10...80, unit: "pt"),
            WelcomeParameter(title: "Hint size", keyPath: \.hintSize, range: 8...40, unit: "pt"),
            WelcomeParameter(title: "Width", keyPath: \.textWidth, range: 200...1400, unit: "pt"),
            WelcomeParameter(title: "Gap below dots", keyPath: \.textGap, range: -100...400, unit: "pt"),
            WelcomeParameter(title: "Darkness", keyPath: \.textOpacity, range: 0.1...1),
        ]),
    ]
}
