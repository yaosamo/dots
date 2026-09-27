import AVFoundation
import QuartzCore
import Vision

/// Finds your face in the camera's frames (Vision, on this Mac) so the blob can reach toward where
/// your head goes. Runs on the session's frames queue, at most `rate` times a second, and only while
/// it's the frames output's delegate (see CameraController: the blob, while the camera is open).
final class HeadTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private static let rate: Double = 20

    /// The biggest face's center, 0…1 across and up the unmirrored frame (Vision's coordinates),
    /// or nil when there's no face; and the frame's size in pixels. Called on the frames queue.
    private let onFace: (CGPoint?, CGSize) -> Void
    private let request = VNDetectFaceRectanglesRequest()
    private var lastRun: CFTimeInterval = 0

    init(onFace: @escaping (CGPoint?, CGSize) -> Void) {
        self.onFace = onFace
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        guard now - lastRun >= 1 / Self.rate, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastRun = now
        let size = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        try? VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request])
        let face = request.results?.max { $0.boundingBox.width < $1.boundingBox.width }
        onFace(face.map { CGPoint(x: $0.boundingBox.midX, y: $0.boundingBox.midY) }, size)
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
