import Foundation

/// Every knob of the first-launch welcome: timings, clouds, dots and text.
enum WelcomeTuning {
    struct Values: Equatable {
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
        // Clouds' cost
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
        var textGap: Double = 56
        var textOpacity: Double = 0.85
    }

    static let values = Values()
}
