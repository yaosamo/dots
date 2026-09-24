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

            // Sized like the bubble; Spacer and the message don't take clicks, so drags reach the bubble.
            VStack {
                if model.isDenied {
                    Spacer()
                    deniedMessage.allowsHitTesting(false)
                }
                Spacer()
                if isHovering {
                    controls
                        .padding(.bottom, model.shape == .circle ? size.height * 0.12 : 12)
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
                symbol: model.shape == .circle ? "rectangle.portrait" : "circle",
                help: model.shape == .circle ? "Portrait rectangle" : "Circle",
                action: model.toggleShape
            )
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

private struct BubbleHost: NSViewRepresentable {
    let view: CameraBubbleView

    func makeNSView(context: Context) -> CameraBubbleView { view }
    func updateNSView(_ nsView: CameraBubbleView, context: Context) {}
}

/// Mirrored live preview clipped to a rounded rect, centered in the view. Dragging it moves the window.
final class CameraBubbleView: NSView {
    private let shadowLayer = CALayer()
    private let clipLayer = CALayer()
    private let previewLayer: AVCaptureVideoPreviewLayer
    private var startObserver: NSObjectProtocol?

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

    override func layout() {
        super.layout()
        // Keep the bubble centered in the (fixed-size) window, without animating.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        shadowLayer.position = center
        clipLayer.position = center
        CATransaction.commit()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    /// Selfie cameras should feel like a mirror. The connection only exists once capture has an input.
    private func mirror() {
        guard let connection = previewLayer.connection, connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = true
    }
}
