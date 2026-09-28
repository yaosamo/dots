import AVFoundation
import QuartzCore
import Vision

/// Finds your hand, or else your face, in the camera's frames (Vision, on this Mac) so the blob can
/// grow toward it. Runs on the session's frames queue, at most `rate` times a second, and only while
/// it's the frames output's delegate (see CameraController: the blob, while the camera is open).
final class HeadTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private static let rate: Double = 10

    /// A hand's center if one's up, else the biggest face's, 0…1 across and up the unmirrored frame
    /// (Vision's coordinates), or nil when there's neither; and the frame's size in pixels. Called on
    /// the frames queue.
    private let onTarget: (CGPoint?, CGSize) -> Void
    private let faces = VNDetectFaceRectanglesRequest()
    private let hands: VNDetectHumanHandPoseRequest = {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 1
        return request
    }()
    private var lastRun: CFTimeInterval = 0
    /// Hands are looked for every third run (the heavier request); in between, the last one stands.
    private var runs = 0
    private var lastHand: CGPoint?

    init(onTarget: @escaping (CGPoint?, CGSize) -> Void) {
        self.onTarget = onTarget
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        guard now - lastRun >= 1 / Self.rate, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastRun = now
        let size = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        runs += 1
        let looksForHands = runs % 3 == 0
        try? VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up)
            .perform(looksForHands ? [faces, hands] : [faces])
        if looksForHands { lastHand = Self.handCenter(hands.results?.first) }
        let face = faces.results?.max { $0.boundingBox.width < $1.boundingBox.width }
            .map { CGPoint(x: $0.boundingBox.midX, y: $0.boundingBox.midY) }
        onTarget(lastHand ?? face, size)
    }

    /// The middle of the hand's confidently seen joints; nil unless enough of it is seen.
    private static func handCenter(_ hand: VNHumanHandPoseObservation?) -> CGPoint? {
        guard let points = try? hand?.recognizedPoints(.all) else { return nil }
        let seen = points.values.filter { $0.confidence > 0.4 }
        guard seen.count >= 8 else { return nil }
        let x = seen.map(\.location.x).reduce(0, +) / CGFloat(seen.count)
        let y = seen.map(\.location.y).reduce(0, +) / CGFloat(seen.count)
        return CGPoint(x: x, y: y)
    }
}

/// Where the blob is reaching: a direction and strength (0…1) in the bubble's Core Animation
/// coordinates (y up), eased toward the tracked target so it glides rather than twitches. The video's
/// mask and the effect rim both read `current(at:)` each frame, so they stretch as one.
@MainActor
final class BlobPull {
    static let shared = BlobPull()

    var target = CGVector.zero
    private var value = CGVector.zero
    private var lastTime: TimeInterval = 0

    /// Advances the easing to `time` (calls within the same frame get the same value).
    func current(at time: TimeInterval) -> CGVector {
        let step = min(max(time - lastTime, 0), 0.1)
        lastTime = time
        let follow = CGFloat(1 - exp(-step * 7))
        value.dx += (target.dx - value.dx) * follow
        value.dy += (target.dy - value.dy) * follow
        return value
    }
}
