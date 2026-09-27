import Foundation

/// Every knob of the first-launch welcome, edited live in Welcome Lab (menu bar menu). Values
/// persist between launches. Welcome Lab's "Copy" produces a `Values(...)` literal; paste it over
/// the defaults below to make a tuning permanent.
@MainActor
final class WelcomeTuning: ObservableObject {
    /// How lightning shows while the storm gathers.
    enum Lightning: Int, CaseIterable, Identifiable {
        case none, glow, bolts, sheet

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .none: "None"
            case .glow: "Glow"
            case .bolts: "Bolts"
            case .sheet: "Sheet"
            }
        }
    }

    /// What's behind the dots: the storm that blooms open, Onlook's flow with ink that trails
    /// the pointer (Onboarding/FlowBackground.swift), or clouds that come down over the screen
    /// (Shaders/CloudShader.metal).
    enum Background: Int, CaseIterable, Identifiable {
        case storm, flow, clouds

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .storm: "Storm"
            case .flow: "Flow"
            case .clouds: "Clouds"
            }
        }
    }

    struct Values: Codable, Equatable {
        /// A `Background` raw value (kept as a number so it copies and saves like the rest).
        var background: Double = 2
        // Timing, in seconds
        var fadeIn: Double = 1.4
        /// From opening until the bloom bursts; the storm gathers and darkens meanwhile.
        var gather: Double = 5.2
        var bloom: Double = 1.2
        var burst: Double = 1.4
        /// After the bloom bursts, before the first dot.
        var dotsDelay: Double = 0.7
        var dotBeat: Double = 0.35
        var dotEmerge: Double = 0.9
        /// After the last dot, before the text.
        var textDelay: Double = 0.7
        /// After the text, before the hint and Done.
        var hintDelay: Double = 0.8
        // Clouds (Shaders/CloudShader.metal)
        /// From opening until the clouds have come down; the first dot follows after `dotsDelay`.
        var cloudDescend: Double = 1.636
        /// Once Done lands the dots, the clouds lift away over this.
        var cloudLeave: Double = 0.6
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
        // Storm (Shaders/WelcomeShader.metal)
        var cloudScale: Double = 2.6
        /// Lower is cloudier.
        var cloudCover: Double = 0.38
        var swirl: Double = 2.2
        var drift: Double = 0.04
        /// How soft the edge of the closing darkness is.
        var darknessSoftness: Double = 0.35
        /// The sky's darkest grey.
        var darkest: Double = 0.04
        // Lightning
        /// A `Lightning` raw value (kept as a number so it copies and saves like the rest).
        var lightning: Double = 0
        var lightningStrength: Double = 1
        var strikes: Double = 6
        // Bloom
        var bloomRim: Double = 1.2
        var bloomPop: Double = 0.35
        // Dots, in points
        var dotSize: Double = 120
        var dotSpacing: Double = 168
        /// From the screen's middle; negative is up.
        var dotsOffsetY: Double = -10
        var dotBlur: Double = 18
        var dotStartScale: Double = 0.8
        // Text
        var message: String = "hello, we’re dots - small and fun everyday tools for your computer"
        var hint: String = "click a dot to see what it does"
        var textSize: Double = 28
        var hintSize: Double = 16
        var textWidth: Double = 560
        /// From the dots' bottom edge to the text's top.
        var textGap: Double = 30
        var textOpacity: Double = 0.85
    }

    static let shared = WelcomeTuning()
    private static let defaultsKey = "welcomeTuning"

    @Published var values: Values {
        didSet { save() }
    }

    private init() {
        // A saved tuning from an older set of fields fails to decode; fall back to the defaults.
        values = UserDefaults.standard.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(Values.self, from: $0) } ?? Values()
    }

    var background: Background {
        get { Background(rawValue: Int(values.background.rounded())) ?? .clouds }
        set { values.background = Double(newValue.rawValue) }
    }

    var lightning: Lightning {
        get { Lightning(rawValue: Int(values.lightning.rounded())) ?? .glow }
        set { values.lightning = Double(newValue.rawValue) }
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
            WelcomeParameter(title: "Fade in", keyPath: \.fadeIn, range: 0.1...4, unit: "s"),
            WelcomeParameter(title: "Storm gathers for", keyPath: \.gather, range: 1...12, unit: "s"),
            WelcomeParameter(title: "Bloom sweep", keyPath: \.bloom, range: 0.2...4, unit: "s"),
            WelcomeParameter(title: "Clouds blow apart", keyPath: \.burst, range: 0.2...4, unit: "s"),
            WelcomeParameter(title: "First dot after bloom", keyPath: \.dotsDelay, range: 0...3, unit: "s"),
            WelcomeParameter(title: "Between dots", keyPath: \.dotBeat, range: 0...1.5, unit: "s"),
            WelcomeParameter(title: "Dot emerges over", keyPath: \.dotEmerge, range: 0.1...3, unit: "s"),
            WelcomeParameter(title: "Text after last dot", keyPath: \.textDelay, range: 0...3, unit: "s"),
            WelcomeParameter(title: "Hint and Done after text", keyPath: \.hintDelay, range: 0...3, unit: "s"),
        ]),
        WelcomeSection(title: "Clouds", parameters: [
            WelcomeParameter(title: "Come down over", keyPath: \.cloudDescend, range: 0.5...8, unit: "s"),
            WelcomeParameter(title: "Lift away over", keyPath: \.cloudLeave, range: 0.1...2, unit: "s"),
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
        WelcomeSection(title: "Storm", parameters: [
            WelcomeParameter(title: "Cloud size", keyPath: \.cloudScale, range: 0.5...8),
            WelcomeParameter(title: "Cloud cover", keyPath: \.cloudCover, range: 0.1...0.7),
            WelcomeParameter(title: "Swirl", keyPath: \.swirl, range: 0...6),
            WelcomeParameter(title: "Drift speed", keyPath: \.drift, range: 0...0.3),
            WelcomeParameter(title: "Darkness edge softness", keyPath: \.darknessSoftness, range: 0.02...1),
            WelcomeParameter(title: "Darkest sky", keyPath: \.darkest, range: 0...0.5),
        ]),
        WelcomeSection(title: "Lightning", parameters: [
            WelcomeParameter(title: "Strength", keyPath: \.lightningStrength, range: 0...3),
            WelcomeParameter(title: "Strikes", keyPath: \.strikes, range: 0...16, step: 1),
        ]),
        WelcomeSection(title: "Bloom", parameters: [
            WelcomeParameter(title: "Edge brightness", keyPath: \.bloomRim, range: 0...3),
            WelcomeParameter(title: "Burst flash", keyPath: \.bloomPop, range: 0...1),
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
