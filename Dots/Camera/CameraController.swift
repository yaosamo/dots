import AppKit
import SwiftUI

@MainActor
final class CameraModel: ObservableObject {
    enum Shape: String { case circle, portrait }

    /// The expand button steps small → medium → large, then back to small.
    enum Size: String, CaseIterable {
        case small, medium, large

        var scale: CGFloat {
            switch self {
            case .small: 1
            case .medium: 1.5
            case .large: 2
            }
        }

        var next: Size {
            let all = Size.allCases
            return all[(all.firstIndex(of: self)! + 1) % all.count]
        }
    }

    static let padding: CGFloat = 12

    /// Shared by the Core Animation bubble and the SwiftUI controls so they move as one.
    static let morphDuration: TimeInterval = 0.3
    static let morphCurve: (Double, Double, Double, Double) = (0.3, 0, 0.2, 1)
    static var morphAnimation: Animation {
        .timingCurve(morphCurve.0, morphCurve.1, morphCurve.2, morphCurve.3, duration: morphDuration)
    }

    @Published private(set) var shape: Shape = .circle
    @Published private(set) var size: Size = .small
    @Published var isDenied = false

    let session = CameraSession()
    var onClose: (() -> Void)?
    var onLayoutRequest: ((Shape, Size) -> Void)?

    var contentSize: CGSize { Self.contentSize(shape: shape, size: size) }
    var cornerRadius: CGFloat { Self.cornerRadius(shape: shape, size: size) }

    func stepSize() { onLayoutRequest?(shape, size.next) }
    func toggleShape() { onLayoutRequest?(shape == .circle ? .portrait : .circle, size) }

    /// Only the controller applies layout, so the bubble and controls animate together.
    fileprivate func apply(shape: Shape, size: Size) {
        self.shape = shape
        self.size = size
    }

    static func contentSize(shape: Shape, size: Size) -> CGSize {
        let scale = size.scale
        switch shape {
        case .circle: return CGSize(width: 160 * scale, height: 160 * scale)
        case .portrait: return CGSize(width: 150 * scale, height: 200 * scale)
        }
    }

    /// A circle is a rounded rectangle whose radius is half its side — which is what lets it morph.
    static func cornerRadius(shape: Shape, size: Size) -> CGFloat {
        switch shape {
        case .circle: return contentSize(shape: shape, size: size).width / 2
        case .portrait: return 20 * (size.scale + 1) / 2 // 20, 25, 30
        }
    }

    /// The window stays this size — big enough for every bubble — and never resizes, so nothing
    /// in it gets re-laid out mid-morph. Its transparent margin lets clicks through to what's below.
    static let windowSize: CGSize = {
        let sizes = [Shape.circle, .portrait].flatMap { shape in
            Size.allCases.map { contentSize(shape: shape, size: $0) }
        }
        return CGSize(width: sizes.map(\.width).max()! + padding * 2,
                      height: sizes.map(\.height).max()! + padding * 2)
    }()
}

@MainActor
final class CameraController: DotFeature {
    private let model = CameraModel()
    private let bubble: CameraBubbleView
    private let panel = FloatingPanel(level: DotsLevel.camera, keyable: false)
    private let onVisibilityChange: (Bool) -> Void
    private var hasPositioned = false

    private(set) var isVisible = false

    init(onVisibilityChange: @escaping (Bool) -> Void) {
        self.onVisibilityChange = onVisibilityChange
        bubble = CameraBubbleView(session: model.session.session)
        bubble.setBubble(size: model.contentSize, cornerRadius: model.cornerRadius, duration: 0)
        panel.contentView = FirstClickHostingView(rootView: CameraView(model: model, bubble: bubble))
        model.onClose = { [weak self] in self?.hide() }
        model.onLayoutRequest = { [weak self] in self?.morph(to: $0, size: $1) }
    }

    func show() {
        let shownAt = ProcessInfo.processInfo.systemUptime
        if !hasPositioned { placeInitially() }
        model.isDenied = false
        model.session.start { [weak self] in self?.model.isDenied = true }
        panel.orderFrontRegardless()
        isVisible = true
        onVisibilityChange(true)
        Log.camera.debug("Panel shown in \(Log.ms(since: shownAt), format: .fixed(precision: 1)) ms (video appears once startRunning finishes)")
    }

    func hide() {
        panel.orderOut(nil)
        model.session.stop()
        isVisible = false
        onVisibilityChange(false)
        Log.camera.debug("Panel hidden")
    }

    /// Bubble 24pt from the bottom-right corner of the main screen on first show; draggable after.
    private func placeInitially() {
        guard let visible = NSScreen.primary?.visibleFrame else { return }
        let window = CameraModel.windowSize
        let bubble = model.contentSize
        let center = NSPoint(x: visible.maxX - 24 - bubble.width / 2, y: visible.minY + 24 + bubble.height / 2)
        let origin = NSPoint(x: center.x - window.width / 2, y: center.y - window.height / 2)
        panel.setFrame(NSRect(origin: origin, size: window), display: true)
        hasPositioned = true
    }

    /// Morphs around the bubble's center. Core Animation morphs the bubble's size and corner radius;
    /// SwiftUI moves the controls on the identical curve. The window itself never changes.
    private func morph(to shape: CameraModel.Shape, size: CameraModel.Size) {
        let requestedAt = ProcessInfo.processInfo.systemUptime
        if let event = NSApp.currentEvent {
            Log.camera.debug("Morph → \(shape.rawValue, privacy: .public) \(size.rawValue, privacy: .public), handler ran \((requestedAt - event.timestamp) * 1000, format: .fixed(precision: 1)) ms after the click")
        }

        withAnimation(CameraModel.morphAnimation) {
            model.apply(shape: shape, size: size)
        }
        bubble.setBubble(size: model.contentSize, cornerRadius: model.cornerRadius, duration: CameraModel.morphDuration) {
            Log.camera.debug("Morph finished \(Log.ms(since: requestedAt), format: .fixed(precision: 0)) ms after request (target \(CameraModel.morphDuration * 1000, format: .fixed(precision: 0)) ms)")
        }
        Log.camera.debug("Morph started \(Log.ms(since: requestedAt), format: .fixed(precision: 1)) ms after request, window \(Int(self.panel.frame.width))×\(Int(self.panel.frame.height)) (fixed)")
    }
}
