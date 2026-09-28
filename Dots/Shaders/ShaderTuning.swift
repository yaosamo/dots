import Foundation

/// Live-tweakable shader and transition parameters, edited in Shader Lab (menu bar menu, debug builds).
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
        #if DEBUG
        // A saved tuning from an older set of fields fails to decode; fall back to the defaults.
        values = UserDefaults.standard.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(Values.self, from: $0) } ?? Values()
        #else
        // Releases always use the defaults below: the labs, which change them, are debug-only.
        values = Values()
        #endif
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

#if DEBUG
/// Shader Lab's sliders, section by section.
enum ShaderLabSections {
    static let all: [LabSection<ShaderTuning.Values>] = [
        LabSection(title: "Tasks frost", parameters: [
            LabParameter(title: "Blotch size", keyPath: \.frostScale, range: 40...600, unit: "pt"),
            LabParameter(title: "Octaves (detail)", keyPath: \.frostOctaves, range: 1...8, step: 1),
            LabParameter(title: "Softness", keyPath: \.frostSoft, range: 0.02...0.5),
            LabParameter(title: "Edge bias", keyPath: \.frostEdgeBias, range: 0...1),
            LabParameter(title: "Open duration", keyPath: \.frostInDuration, range: 0.1...3, unit: "s"),
            LabParameter(title: "Close duration", keyPath: \.frostOutDuration, range: 0.1...3, unit: "s"),
        ]),
        LabSection(title: "Electric", parameters: [
            LabParameter(title: "Jitter", keyPath: \.electricJitter, range: 0...30, unit: "pt"),
            LabParameter(title: "Crackle rate", keyPath: \.electricRate, range: 1...40, unit: "/s"),
            LabParameter(title: "Glow radius", keyPath: \.electricGlow, range: 2...24, unit: "pt"),
        ]),
        LabSection(title: "Fire", parameters: [
            LabParameter(title: "Flame height", keyPath: \.fireHeight, range: 5...80, unit: "pt"),
            LabParameter(title: "Rise speed", keyPath: \.fireSpeed, range: 0...8),
            LabParameter(title: "Wobble", keyPath: \.fireWobble, range: 0...30, unit: "pt"),
        ]),
        LabSection(title: "Rainbow", parameters: [
            LabParameter(title: "Band density", keyPath: \.rainbowScale, range: 0.2...6),
            LabParameter(title: "Drift speed", keyPath: \.rainbowSpeed, range: 0...2),
        ]),
    ]
}
#endif
