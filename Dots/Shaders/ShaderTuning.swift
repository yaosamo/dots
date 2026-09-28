import Foundation

/// Shader and transition parameters.
enum ShaderTuning {
    struct Values: Equatable {
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

    static let values = Values()
}
