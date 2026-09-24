import Foundation

/// Live-tweakable shader and transition parameters, edited in Shader Lab (menu bar menu).
/// Values persist between launches. Shader Lab's "Copy" produces a `Values(...)` literal; paste it
/// over the defaults below to make a tuning permanent.
@MainActor
final class ShaderTuning: ObservableObject {
    struct Values: Codable, Equatable {
        // Tasks frost (Shaders/FrostShader.metal)
        var frostScale: Double = 474.57
        var frostOctaves: Double = 8
        var frostSoft: Double = 0.391
        var frostEdgeBias: Double = 0
        var frostInDuration: Double = 0.528
        var frostOutDuration: Double = 0.35
        // Pen brushes (Shaders/PenShaders.metal)
        var electricJitter: Double = 21.795
        var electricRate: Double = 10.42
        var electricGlow: Double = 9.7
        var fireHeight: Double = 22.148
        var fireSpeed: Double = 0.956
        var fireWobble: Double = 30
        var rainbowScale: Double = 0.88
        var rainbowSpeed: Double = 0.728
    }

    static let shared = ShaderTuning()
    private static let defaultsKey = "shaderTuning"

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
            guard let label = child.label, let value = child.value as? Double else { return nil }
            return "    \(label): \(Self.format(value))"
        }
        return "ShaderTuning.Values(\n" + fields.joined(separator: ",\n") + "\n)"
    }

    static func format(_ value: Double) -> String {
        String(format: "%g", (value * 1000).rounded() / 1000)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}

/// One slider in Shader Lab.
struct TuningParameter: Identifiable {
    let title: String
    let keyPath: WritableKeyPath<ShaderTuning.Values, Double>
    let range: ClosedRange<Double>
    var step: Double?
    var unit = ""

    var id: String { title }
}

struct TuningSection: Identifiable {
    let title: String
    let parameters: [TuningParameter]

    var id: String { title }

    static let all: [TuningSection] = [
        TuningSection(title: "Tasks frost", parameters: [
            TuningParameter(title: "Blotch size", keyPath: \.frostScale, range: 40...600, unit: "pt"),
            TuningParameter(title: "Octaves (detail)", keyPath: \.frostOctaves, range: 1...8, step: 1),
            TuningParameter(title: "Softness", keyPath: \.frostSoft, range: 0.02...0.5),
            TuningParameter(title: "Edge bias", keyPath: \.frostEdgeBias, range: 0...1),
            TuningParameter(title: "Open duration", keyPath: \.frostInDuration, range: 0.1...3, unit: "s"),
            TuningParameter(title: "Close duration", keyPath: \.frostOutDuration, range: 0.1...3, unit: "s"),
        ]),
        TuningSection(title: "Electric", parameters: [
            TuningParameter(title: "Jitter", keyPath: \.electricJitter, range: 0...30, unit: "pt"),
            TuningParameter(title: "Crackle rate", keyPath: \.electricRate, range: 1...40, unit: "/s"),
            TuningParameter(title: "Glow radius", keyPath: \.electricGlow, range: 2...24, unit: "pt"),
        ]),
        TuningSection(title: "Fire", parameters: [
            TuningParameter(title: "Flame height", keyPath: \.fireHeight, range: 5...80, unit: "pt"),
            TuningParameter(title: "Rise speed", keyPath: \.fireSpeed, range: 0...8),
            TuningParameter(title: "Wobble", keyPath: \.fireWobble, range: 0...30, unit: "pt"),
        ]),
        TuningSection(title: "Rainbow", parameters: [
            TuningParameter(title: "Band density", keyPath: \.rainbowScale, range: 0.2...6),
            TuningParameter(title: "Drift speed", keyPath: \.rainbowSpeed, range: 0...2),
        ]),
    ]
}
