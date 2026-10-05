import AppKit
import SwiftUI

@MainActor
final class CameraModel: ObservableObject {
    /// The shape button steps circle → portrait → blob, then back to circle.
    enum Shape: String, CaseIterable {
        case circle, portrait, blob

        var next: Shape {
            let all = Shape.allCases
            return all[(all.firstIndex(of: self)! + 1) % all.count]
        }

        var symbol: String {
            switch self {
            case .circle: "circle"
            case .portrait: "rectangle.portrait"
            case .blob: "drop"
            }
        }

        var title: String {
            switch self {
            case .circle: "Circle"
            case .portrait: "Portrait rectangle"
            case .blob: "Blob"
            }
        }
    }

    /// One of the pen's shader brushes around the bubble's edge, or none.
    enum Effect: String, CaseIterable {
        case none, electric, fire, rainbow, cloud

        var brush: Brush? {
            switch self {
            case .none: nil
            case .electric: .electric
            case .fire: .fire
            case .rainbow: .rainbow
            case .cloud: nil
            }
        }

        var symbol: String {
            switch self {
            case .none: "sparkles"
            case .electric: "bolt.fill"
            case .fire: "flame.fill"
            case .rainbow: "rainbow"
            case .cloud: "cloud.fill"
            }
        }

        var help: String {
            switch self {
            case .none: "Effect: none"
            case .electric: "Effect: electric"
            case .fire: "Effect: fire"
            case .rainbow: "Effect: rainbow"
            case .cloud: "Effect: cloud"
            }
        }

        var next: Effect {
            let all = Effect.allCases
            return all[(all.firstIndex(of: self)! + 1) % all.count]
        }
    }

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

    /// Room around the biggest bubble for its effect's glow and flames (the fire's are tallest).
    static let padding: CGFloat = 64
    private static let effectKey = "camera.effect"

    /// Shared by the Core Animation bubble and the SwiftUI controls so they move as one.
    static let morphDuration: TimeInterval = 0.3
    static let morphCurve: (Double, Double, Double, Double) = (0.3, 0, 0.2, 1)
    static var morphAnimation: Animation {
        .timingCurve(morphCurve.0, morphCurve.1, morphCurve.2, morphCurve.3, duration: morphDuration)
    }

    @Published private(set) var shape: Shape = .circle
    @Published private(set) var size: Size = .small
    @Published var isDenied = false
    /// Whether the camera is on screen: the effect rim only animates while it is (a hidden window's
    /// SwiftUI animations keep running otherwise).
    @Published var isShown = false
    @Published private(set) var effect = Effect(rawValue: UserDefaults.standard.string(forKey: effectKey) ?? "") ?? .none {
        didSet { UserDefaults.standard.set(effect.rawValue, forKey: Self.effectKey) }
    }

    /// The chosen camera (nil: the built-in one) and microphone (nil: none), kept between launches.
    @Published private(set) var cameraID = UserDefaults.standard.string(forKey: CameraSession.cameraKey) {
        didSet { UserDefaults.standard.set(cameraID, forKey: CameraSession.cameraKey) }
    }
    @Published private(set) var microphoneID = UserDefaults.standard.string(forKey: CameraSession.microphoneKey) {
        didSet { UserDefaults.standard.set(microphoneID, forKey: CameraSession.microphoneKey) }
    }
    @Published private(set) var isMicrophoneDenied = false

    lazy var session = CameraSession(cameraID: cameraID, microphoneID: microphoneID)
    var onClose: (() -> Void)?
    var onLayoutRequest: ((Shape, Size) -> Void)?

    var contentSize: CGSize { Self.contentSize(shape: shape, size: size) }
    var cornerRadius: CGFloat { Self.cornerRadius(shape: shape, size: size) }

    func stepSize() { onLayoutRequest?(shape, size.next) }
    func toggleShape() { onLayoutRequest?(shape.next, size) }
    func stepEffect() { effect = effect.next }

    func selectCamera(_ id: String) {
        cameraID = id
        session.selectCamera(id: id)
    }

    func selectMicrophone(_ id: String?) {
        microphoneID = id
        isMicrophoneDenied = false
        session.selectMicrophone(id: id) { [weak self] in self?.isMicrophoneDenied = true }
    }

    /// Every camera and microphone, with the ones in use checked, at the pointer. AppKit's menu
    /// rather than SwiftUI's: the hover controls it's opened from go away under it.
    func showDeviceMenu() {
        let menu = NSMenu()
        menu.addItem(.sectionHeader(title: "Camera"))
        let camera = CameraSession.camera(id: cameraID)?.uniqueID
        let cameras = CameraSession.cameras()
        if cameras.isEmpty { menu.addItem(DeviceMenuItem(title: "No camera found", isOn: false, action: nil)) }
        for device in cameras {
            menu.addItem(DeviceMenuItem(title: device.localizedName, isOn: device.uniqueID == camera) { [weak self] in
                self?.selectCamera(device.uniqueID)
            })
        }

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Microphone"))
        let microphones = CameraSession.microphones()
        let microphone = microphones.first { $0.uniqueID == microphoneID && !isMicrophoneDenied }?.uniqueID
        menu.addItem(DeviceMenuItem(title: "None", isOn: microphone == nil) { [weak self] in
            self?.selectMicrophone(nil)
        })
        for device in microphones {
            menu.addItem(DeviceMenuItem(title: device.localizedName, isOn: device.uniqueID == microphone) { [weak self] in
                self?.selectMicrophone(device.uniqueID)
            })
        }
        if isMicrophoneDenied {
            menu.addItem(DeviceMenuItem(title: "Allow Microphone in System Settings…", isOn: false) {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
            })
        } else {
            let hint = NSMenuItem(title: "The bubble's edge glows as you speak", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
        }
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    /// Only the controller applies layout, so the bubble and controls animate together.
    fileprivate func apply(shape: Shape, size: Size) {
        self.shape = shape
        self.size = size
    }

    static func contentSize(shape: Shape, size: Size) -> CGSize {
        let scale = size.scale
        switch shape {
        case .circle, .blob: return CGSize(width: 160 * scale, height: 160 * scale)
        case .portrait: return CGSize(width: 150 * scale, height: 200 * scale)
        }
    }

    /// A circle is a rounded rectangle whose radius is half its side — which is what lets it morph.
    static func cornerRadius(shape: Shape, size: Size) -> CGFloat {
        switch shape {
        case .circle, .blob: return contentSize(shape: shape, size: size).width / 2
        case .portrait: return 20 * (size.scale + 1) / 2 // 20, 25, 30
        }
    }

    /// The window stays this size — big enough for every bubble — and never resizes, so nothing
    /// in it gets re-laid out mid-morph. Its transparent margin lets clicks through to what's below.
    static let windowSize: CGSize = {
        let sizes = Shape.allCases.flatMap { shape in
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
    private lazy var tracker = HeadTracker(onTarget: { [weak self] point, size in
        DispatchQueue.main.async { self?.bubble.trackedMoved(to: point, videoSize: size) }
    })

    init(onVisibilityChange: @escaping (Bool) -> Void) {
        self.onVisibilityChange = onVisibilityChange
        bubble = CameraBubbleView(session: model.session.session)
        bubble.setBubble(size: model.contentSize, cornerRadius: model.cornerRadius, duration: 0)
        panel.contentView = FirstClickHostingView(rootView: CameraView(model: model, bubble: bubble))
        model.onClose = { [weak self] in self?.hide() }
        model.onLayoutRequest = { [weak self] in self?.morph(to: $0, size: $1) }
        model.session.onCameraChange = { [weak bubble] in bubble?.mirror() }
        model.session.onVoiceLevel = { [weak bubble] in bubble?.setVoiceLevel($0) }
    }

    func show() {
        let shownAt = ProcessInfo.processInfo.systemUptime
        if !hasPositioned { placeInitially() }
        model.isDenied = false
        model.session.start { [weak self] in self?.model.isDenied = true }
        panel.orderFrontRegardless()
        isVisible = true
        model.isShown = true
        bubble.setBlob(model.shape == .blob, duration: 0)
        updateTracking()
        onVisibilityChange(true)
        Log.camera.debug("Panel shown in \(Log.ms(since: shownAt), format: .fixed(precision: 1)) ms (video appears once startRunning finishes)")
    }

    func hide() {
        panel.orderOut(nil)
        model.session.stop()
        isVisible = false
        model.isShown = false
        updateTracking()
        onVisibilityChange(false)
        Log.camera.debug("Panel hidden")
    }

    /// Head and hand tracking run only for the blob, while the camera is open.
    private func updateTracking() {
        let isOn = isVisible && model.shape == .blob
        model.session.setFrameDelegate(isOn ? tracker : nil)
        if !isOn { BlobPull.shared.target = .zero }
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
        bubble.setBlob(shape == .blob, duration: CameraModel.morphDuration)
        updateTracking()
        bubble.setBubble(size: model.contentSize, cornerRadius: model.cornerRadius, duration: CameraModel.morphDuration) {
            Log.camera.debug("Morph finished \(Log.ms(since: requestedAt), format: .fixed(precision: 0)) ms after request (target \(CameraModel.morphDuration * 1000, format: .fixed(precision: 0)) ms)")
        }
        Log.camera.debug("Morph started \(Log.ms(since: requestedAt), format: .fixed(precision: 1)) ms after request, window \(Int(self.panel.frame.width))×\(Int(self.panel.frame.height)) (fixed)")
    }
}

/// A checkable menu item that runs a closure (nil: disabled).
private final class DeviceMenuItem: NSMenuItem {
    private let run: (() -> Void)?

    init(title: String, isOn: Bool, action run: (() -> Void)?) {
        self.run = run
        super.init(title: title, action: run == nil ? nil : #selector(runAction), keyEquivalent: "")
        target = self
        state = isOn ? .on : .off
        isEnabled = run != nil
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func runAction() { run?() }
}
