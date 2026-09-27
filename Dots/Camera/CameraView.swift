import AVFoundation
import SwiftUI

/// SwiftUI only draws the hover controls; the bubble itself is a Core Animation layer tree.
struct CameraView: View {
    @ObservedObject var model: CameraModel
    let bubble: CameraBubbleView

    @State private var isHovering = false

    var body: some View {
        let size = model.contentSize

        ZStack {
            BubbleHost(view: bubble)
            if let brush = model.effect.brush {
                EffectRim(brush: brush, size: size, cornerRadius: model.cornerRadius,
                          blob: model.shape == .blob ? 1 : 0)
                    .transition(.opacity)
            }

            // Sized like the bubble; Spacer and the message don't take clicks, so drags reach the bubble.
            VStack {
                if model.isDenied {
                    Spacer()
                    deniedMessage.allowsHitTesting(false)
                }
                Spacer()
                if isHovering {
                    controls
                        .padding(.bottom, model.shape == .portrait ? 12 : size.height * 0.12)
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Hover counts only over the bubble, not the window's transparent margin.
        .onContinuousHover { phase in
            let isInside: Bool
            switch phase {
            case .active(let location): isInside = bubbleRect.contains(location)
            case .ended: isInside = false
            }
            guard isInside != isHovering else { return }
            withAnimation(.easeOut(duration: 0.15)) { isHovering = isInside }
        }
        .environment(\.colorScheme, .dark)
    }

    private var bubbleRect: CGRect {
        let window = CameraModel.windowSize
        let size = model.contentSize
        return CGRect(x: (window.width - size.width) / 2, y: (window.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    private var controls: some View {
        HStack(spacing: 2) {
            ControlButton(
                symbol: model.size == .large ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                help: model.size == .large ? "Make small" : "Make bigger",
                action: model.stepSize
            )
            ControlButton(
                symbol: model.shape.next.symbol,
                help: model.shape.next.title,
                action: model.toggleShape
            )
            ControlButton(symbol: model.effect.symbol, help: model.effect.help) {
                withAnimation(.easeOut(duration: 0.2)) { model.stepEffect() }
            }
            ControlButton(symbol: "xmark", help: "Close") { model.onClose?() }
        }
        .padding(3)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private var deniedMessage: some View {
        VStack(spacing: 6) {
            Image(systemName: "video.slash.fill").font(.title2)
            Text("Allow camera in\nSystem Settings › Privacy")
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white.opacity(0.8))
        .padding()
    }
}

private struct ControlButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                // The symbol flips inside the morph's animation; swap it instantly so the old glyph
                // doesn't linger at the old spot while the panel moves.
                .contentTransition(.identity)
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .help(help)
    }
}

/// The pen's shader brush (PenShaders.metal) drawn as a ring on the bubble's edge: a white stroke
/// the shader turns into light, with room around it for the glow and flames. Its size and radius
/// come from the model, so it morphs with the bubble on the same curve.
private struct EffectRim: View {
    let brush: Brush
    let size: CGSize
    let cornerRadius: CGFloat
    /// 0…1 into the blob; animates with the morph.
    let blob: CGFloat

    @ObservedObject private var tuning = ShaderTuning.shared
    @State private var start = Date()

    var body: some View {
        var values = tuning.values
        // The pen's rainbow spans the screen; around a bubble it's tighter, so every hue shows.
        values.rainbowScale *= 3
        let margin = brush.layerMargin(values)
        return TimelineView(.animation) { timeline in
            RimShape(cornerRadius: cornerRadius, blob: blob, time: BlobOutline.now)
                .stroke(brush.inkColor, lineWidth: brush.lineWidth)
                .frame(width: size.width, height: size.height)
                .padding(.horizontal, margin.width)
                .padding(.vertical, margin.height)
                .brushEffect(brush, time: Float(timeline.date.timeIntervalSince(start)), origin: .zero,
                             tuning: values)
        }
        .allowsHitTesting(false)
    }
}

/// The bubble's outline for the rim: its rounded rectangle, or the blob (the same one the video is
/// masked to), with the radius and the blob's amount animating on the morph.
private struct RimShape: Shape {
    var cornerRadius: CGFloat
    var blob: CGFloat
    let time: TimeInterval

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(cornerRadius, blob) }
        set { (cornerRadius, blob) = (newValue.first, newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        guard blob > 0.001 else { return Path(roundedRect: rect, cornerRadius: cornerRadius, style: .circular) }
        let outline = BlobOutline.path(size: rect.size, cornerRadius: cornerRadius, amount: blob, time: time, flipped: true)
        return Path(outline).offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

private struct BubbleHost: NSViewRepresentable {
    let view: CameraBubbleView

    func makeNSView(context: Context) -> CameraBubbleView { view }
    func updateNSView(_ nsView: CameraBubbleView, context: Context) {}
}

/// Mirrored live preview clipped to a rounded rect, or a wobbling blob, centered in the view.
/// Dragging it moves the window.
final class CameraBubbleView: NSView {
    private let shadowLayer = CALayer()
    private let clipLayer = CALayer()
    /// The blob (BlobOutline): the video's mask and its hairline, redrawn every frame while it's on.
    private let blobMask = CAShapeLayer()
    private let blobOutline = CAShapeLayer()
    private var blobLink: CADisplayLink?
    private var blobFrom: CGFloat = 0
    private var blobTo: CGFloat = 0
    private var blobStart: TimeInterval = 0
    private var blobDuration: TimeInterval = 0
    private let previewLayer: AVCaptureVideoPreviewLayer
    private var startObserver: NSObjectProtocol?
    /// Off for previews embedded in another window (Welcome), which shouldn't move with the bubble.
    var dragsWindow = true

    init(session: AVCaptureSession) {
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true

        shadowLayer.backgroundColor = NSColor.black.cgColor
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOpacity = 0.35
        shadowLayer.shadowRadius = 8
        shadowLayer.shadowOffset = CGSize(width: 0, height: -3)

        clipLayer.masksToBounds = true
        clipLayer.cornerCurve = .circular
        clipLayer.backgroundColor = NSColor.black.cgColor
        clipLayer.borderWidth = 1
        clipLayer.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor

        previewLayer.videoGravity = .resizeAspectFill
        clipLayer.addSublayer(previewLayer)
        layer?.addSublayer(shadowLayer)
        layer?.addSublayer(clipLayer)

        blobOutline.fillColor = nil
        blobOutline.strokeColor = NSColor.white.withAlphaComponent(0.25).cgColor
        blobOutline.lineWidth = 1
        blobOutline.isHidden = true
        layer?.addSublayer(blobOutline)

        startObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureSession.didStartRunningNotification, object: session, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.mirror() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Size and radius animate together; circle ↔ rectangle and small ↔ big are the same morph.
    func setBubble(size: CGSize, cornerRadius: CGFloat, duration: TimeInterval, completion: (() -> Void)? = nil) {
        CATransaction.begin()
        if duration > 0 {
            CATransaction.setAnimationDuration(duration)
            let curve = CameraModel.morphCurve
            CATransaction.setAnimationTimingFunction(
                CAMediaTimingFunction(controlPoints: Float(curve.0), Float(curve.1), Float(curve.2), Float(curve.3))
            )
        } else {
            CATransaction.setDisableActions(true)
        }
        CATransaction.setCompletionBlock(completion)
        let bounds = CGRect(origin: .zero, size: size)
        for layer in [shadowLayer, clipLayer] {
            layer.bounds = bounds
            layer.cornerRadius = cornerRadius
        }
        previewLayer.frame = bounds
        CATransaction.commit()
    }

    /// Grows the wobble in (or smooths it away) on the morph's curve, alongside `setBubble`.
    func setBlob(_ isOn: Bool, duration: TimeInterval) {
        blobFrom = currentBlobAmount
        blobTo = isOn ? 1 : 0
        blobStart = CACurrentMediaTime()
        blobDuration = duration
        if blobLink == nil, blobFrom > 0 || blobTo > 0 {
            let link = displayLink(target: self, selector: #selector(stepBlob))
            link.add(to: .main, forMode: .common)
            blobLink = link
        }
        stepBlob()
    }

    private var currentBlobAmount: CGFloat {
        guard blobDuration > 0 else { return blobTo }
        let progress = (CACurrentMediaTime() - blobStart) / blobDuration
        let eased = BlobOutline.ease(progress, curve: CameraModel.morphCurve)
        return blobFrom + (blobTo - blobFrom) * CGFloat(eased)
    }

    /// Redraws the blob from where the bubble's morph is right now, so the two move as one.
    @objc private func stepBlob() {
        // Hidden camera: nothing to draw (the link stays, so it picks up again when shown).
        if window?.isVisible == false, blobTo > 0 { return }
        let amount = currentBlobAmount
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard amount > 0.001 || blobTo > 0 else {
            // Back to the plain rounded rectangle.
            clipLayer.mask = nil
            clipLayer.borderWidth = 1
            shadowLayer.shadowPath = nil
            shadowLayer.backgroundColor = NSColor.black.cgColor
            blobOutline.isHidden = true
            blobLink?.invalidate()
            blobLink = nil
            return
        }
        let current = clipLayer.presentation() ?? clipLayer
        let bounds = CGRect(origin: .zero, size: current.bounds.size)
        let path = BlobOutline.path(size: bounds.size, cornerRadius: current.cornerRadius, amount: amount,
                                    time: BlobOutline.now)
        blobMask.frame = bounds
        blobMask.path = path
        clipLayer.mask = blobMask
        clipLayer.borderWidth = 0
        // The shadow takes the blob's shape; its black fill would show past the wobble.
        shadowLayer.backgroundColor = nil
        shadowLayer.shadowPath = path
        blobOutline.bounds = bounds
        blobOutline.position = clipLayer.position
        blobOutline.path = path
        blobOutline.isHidden = false
    }

    override func layout() {
        super.layout()
        // Keep the bubble centered in the (fixed-size) window, without animating.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        shadowLayer.position = center
        clipLayer.position = center
        blobOutline.position = center
        CATransaction.commit()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard dragsWindow else { return }
        window?.performDrag(with: event)
    }

    /// Selfie cameras should feel like a mirror. The connection only exists once capture has an input.
    private func mirror() {
        guard let connection = previewLayer.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = true
    }
}
