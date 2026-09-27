import CoreGraphics
import Foundation

/// The camera's blob: the bubble's rounded rectangle, sampled all the way round, with each point
/// pulled in by a few slow waves drifting around the edge, so it wobbles like a drop. `amount` 0 is
/// exactly the rounded rectangle, which is what lets any shape morph into the blob. It stays inside
/// the rectangle, so nothing the bubble clips to is ever cut off. Shared by the video's mask
/// (CameraBubbleView) and the effect rim (CameraView), so they wobble as one.
enum BlobOutline {
    private static let samples = 128
    /// How far in the waves pull at most, as a share of the distance to the edge.
    private static let depth: CGFloat = 0.14

    /// Seconds for the drift; the same clock on both sides.
    static var now: TimeInterval { Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000) }

    /// `flipped`: y grows downward (SwiftUI), so the waves land where they do in Core Animation.
    static func path(size: CGSize, cornerRadius: CGFloat, amount: CGFloat, time: TimeInterval,
                     flipped: Bool = false) -> CGPath {
        let half = CGSize(width: size.width / 2, height: size.height / 2)
        let radius = min(cornerRadius, half.width, half.height)
        let path = CGMutablePath()
        for index in 0..<samples {
            let angle = CGFloat(index) / CGFloat(samples) * 2 * .pi
            let direction = CGPoint(x: cos(angle), y: sin(angle))
            let edge = distanceToEdge(along: direction, half: half, radius: radius)
            let t = CGFloat(time)
            let wave = 0.5 * sin(2 * angle + 0.9 * t)
                + 0.3 * sin(3 * angle - 1.3 * t + 1)
                + 0.2 * sin(5 * angle + 1.7 * t + 2) // −1…1
            let distance = edge * (1 - amount * depth * (0.5 + 0.5 * wave))
            let y = direction.y * distance
            let point = CGPoint(x: half.width + direction.x * distance, y: half.height + (flipped ? -y : y))
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    /// From the center out along `direction` to the rounded rectangle's edge (a short bisection on
    /// its signed distance).
    private static func distanceToEdge(along direction: CGPoint, half: CGSize, radius: CGFloat) -> CGFloat {
        var inside: CGFloat = 0
        var outside = hypot(half.width, half.height) + 1
        for _ in 0..<18 {
            let middle = (inside + outside) / 2
            let point = CGPoint(x: direction.x * middle, y: direction.y * middle)
            if signedDistance(point, half: half, radius: radius) < 0 { inside = middle } else { outside = middle }
        }
        return (inside + outside) / 2
    }

    private static func signedDistance(_ point: CGPoint, half: CGSize, radius: CGFloat) -> CGFloat {
        let qx = abs(point.x) - half.width + radius
        let qy = abs(point.y) - half.height + radius
        return hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - radius
    }

    /// Where `progress` (0…1 in time) is along a cubic-bezier timing curve, like CAMediaTimingFunction.
    static func ease(_ progress: Double, curve: (Double, Double, Double, Double)) -> Double {
        let x = min(max(progress, 0), 1)
        func bezier(_ s: Double, _ a: Double, _ b: Double) -> Double {
            3 * (1 - s) * (1 - s) * s * a + 3 * (1 - s) * s * s * b + s * s * s
        }
        var low = 0.0, high = 1.0
        for _ in 0..<24 {
            let middle = (low + high) / 2
            if bezier(middle, curve.0, curve.2) < x { low = middle } else { high = middle }
        }
        return bezier((low + high) / 2, curve.1, curve.3)
    }
}
