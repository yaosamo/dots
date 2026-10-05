import AVFoundation
import QuartzCore

/// Owns the capture session; all session work happens on a private serial queue.
final class CameraSession {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.dots.camera")
    private var isConfigured = false
    private var observers: [NSObjectProtocol] = []

    /// The chosen camera and microphone (`uniqueID`s), set on the session queue. A missing camera
    /// falls back to the default one and comes back when it's plugged in again; nil means no
    /// microphone (the default, so Dots never asks for it unless you pick one).
    private var cameraID: String?
    private var microphoneID: String?
    /// The microphone's level, 0…1, on the main thread, ~30 times a second while there's one.
    var onVoiceLevel: ((CGFloat) -> Void)? {
        get { meter.onLevel }
        set { meter.onLevel = newValue }
    }
    /// Runs on the main thread after the session's camera changed (a pick, or one plugged in or out).
    var onCameraChange: (() -> Void)?
    /// Runs on the main thread when a camera or microphone is plugged in or out.
    var onDevicesChange: (() -> Void)?
    private let meter = VoiceMeter()
    private let audio = AVCaptureAudioDataOutput()
    private let audioQueue = DispatchQueue(label: "app.dots.camera.audio", qos: .userInitiated)

    /// Frames for the head tracker. Only attached to the session while tracking: attached, it has the
    /// camera deliver (and convert) every frame, which costs CPU even with no delegate.
    private let frames: AVCaptureVideoDataOutput = {
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        return output
    }()

    /// The camera's own pixel format, so frames aren't converted, and small (640 wide): tracking a
    /// head or hand needs no more, and the camera scales them for free. The height keeps the camera's
    /// own aspect, which the blob and the pull work out from the frames they're given.
    private func trackingSettings() -> [String: Any] {
        var aspect: CGFloat = 16 / 9
        if let input = input(for: .video) {
            let size = CMVideoFormatDescriptionGetDimensions(input.device.activeFormat.formatDescription)
            if size.width > 0, size.height > 0 { aspect = CGFloat(size.width) / CGFloat(size.height) }
        }
        let height = Int((640 / aspect / 2).rounded()) * 2
        return [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: 640,
            kCVPixelBufferHeightKey as String: height,
        ]
    }
    private let framesQueue = DispatchQueue(label: "app.dots.camera.frames", qos: .userInitiated)

    /// Where the camera's choices are kept, by `uniqueID`.
    static let cameraKey = "camera.device"
    static let microphoneKey = "camera.microphone"

    /// The saved camera by default, so Welcome's preview shows the same one; no microphone.
    init(cameraID: String? = UserDefaults.standard.string(forKey: cameraKey), microphoneID: String? = nil) {
        self.cameraID = cameraID
        self.microphoneID = microphoneID
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: AVCaptureSession.didStartRunningNotification, object: session, queue: nil) { _ in
                Log.camera.debug("Session did start running")
            },
            center.addObserver(forName: AVCaptureSession.didStopRunningNotification, object: session, queue: nil) { _ in
                Log.camera.debug("Session did stop running")
            },
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { note in
                let error = note.userInfo?[AVCaptureSessionErrorKey] as? Error
                Log.camera.error("Session runtime error: \(String(describing: error), privacy: .public)")
            },
            center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { _ in
                Log.camera.info("Session was interrupted (camera in use elsewhere?)")
            },
            center.addObserver(forName: AVCaptureDevice.wasConnectedNotification, object: nil, queue: nil) { [weak self] note in
                self?.devicesChanged(note, connected: true)
            },
            center.addObserver(forName: AVCaptureDevice.wasDisconnectedNotification, object: nil, queue: nil) { [weak self] note in
                self?.devicesChanged(note, connected: false)
            },
        ]
        audio.setSampleBufferDelegate(meter, queue: audioQueue)
    }

    /// Every camera: built-in, USB and other external ones (virtual cameras like OBS's or Camo's
    /// show up as external), an iPhone's Continuity Camera and its Desk View.
    static func cameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
            mediaType: .video, position: .unspecified
        ).devices
    }

    /// Every microphone: built-in, USB, Bluetooth, audio interfaces and virtual ones.
    static func microphones() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio,
                                         position: .unspecified).devices
    }

    /// The chosen camera if it's connected, or else the built-in (or any) one.
    static func camera(id: String?) -> AVCaptureDevice? {
        if let id, let device = AVCaptureDevice(uniqueID: id), device.isConnected, device.hasMediaType(.video) {
            return device
        }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
            ?? AVCaptureDevice.default(for: .video)
    }

    /// The chosen microphone if it's connected and allowed.
    static func microphone(id: String?) -> AVCaptureDevice? {
        guard let id, AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
              let device = AVCaptureDevice(uniqueID: id), device.isConnected, device.hasMediaType(.audio)
        else { return nil }
        return device
    }

    /// Switches to a camera; nil goes back to the default one.
    func selectCamera(id: String?) {
        queue.async {
            self.cameraID = id
            if self.isConfigured { self.applyInputs() }
        }
    }

    /// Switches to a microphone, asking for permission first if needed; nil turns it off.
    /// `onDenied` runs on the main thread.
    func selectMicrophone(id: String?, onDenied: @escaping () -> Void) {
        let apply = {
            self.queue.async {
                self.microphoneID = id
                if self.isConfigured { self.applyInputs() }
            }
        }
        guard id != nil else { return apply() }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            apply()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Log.camera.debug("Microphone permission \(granted ? "granted" : "denied")")
                if granted { apply() } else { DispatchQueue.main.async(execute: onDenied) }
            }
        default:
            onDenied()
        }
    }

    /// Starts capture, asking for permission first if needed. `onDenied` runs on the main thread.
    func start(onDenied: @escaping () -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        Log.camera.debug("start() — authorization \(status.rawValue) (0 undetermined, 2 denied, 3 authorized)")
        switch status {
        case .authorized:
            run()
        case .notDetermined:
            let askedAt = ProcessInfo.processInfo.systemUptime
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Log.camera.debug("Permission \(granted ? "granted" : "denied") after \(Log.ms(since: askedAt), format: .fixed(precision: 0)) ms")
                if granted { self.run() } else { DispatchQueue.main.async(execute: onDenied) }
            }
        default:
            onDenied()
        }
    }

    /// Starts or stops handing frames to `delegate` (nil stops), attaching the frames output only
    /// while there's one.
    func setFrameDelegate(_ delegate: AVCaptureVideoDataOutputSampleBufferDelegate?) {
        queue.async {
            let isAttached = self.session.outputs.contains(self.frames)
            if let delegate {
                self.frames.videoSettings = self.trackingSettings()
                if !isAttached, self.session.canAddOutput(self.frames) {
                    self.session.beginConfiguration()
                    self.session.addOutput(self.frames)
                    self.session.commitConfiguration()
                }
                self.frames.setSampleBufferDelegate(delegate, queue: self.framesQueue)
            } else {
                self.frames.setSampleBufferDelegate(nil, queue: nil)
                if isAttached {
                    self.session.beginConfiguration()
                    self.session.removeOutput(self.frames)
                    self.session.commitConfiguration()
                }
            }
        }
    }

    func stop() {
        let queuedAt = ProcessInfo.processInfo.systemUptime
        queue.async {
            guard self.session.isRunning else { return }
            let startedAt = ProcessInfo.processInfo.systemUptime
            self.session.stopRunning()
            Log.camera.debug("stopRunning took \(Log.ms(since: startedAt), format: .fixed(precision: 1)) ms (waited \((startedAt - queuedAt) * 1000, format: .fixed(precision: 1)) ms in queue)")
            DispatchQueue.main.async { self.onVoiceLevel?(0) }
        }
    }

    private func run() {
        let queuedAt = ProcessInfo.processInfo.systemUptime
        queue.async {
            // A long wait here means a previous stopRunning/startRunning was still blocking the queue.
            Log.camera.debug("Session queue picked up start after \(Log.ms(since: queuedAt), format: .fixed(precision: 1)) ms")
            if !self.isConfigured { self.configure() }
            guard !self.session.isRunning else { return }
            let startedAt = ProcessInfo.processInfo.systemUptime
            self.session.startRunning()
            Log.camera.debug("startRunning took \(Log.ms(since: startedAt), format: .fixed(precision: 1)) ms")
        }
    }

    private func configure() {
        let startedAt = ProcessInfo.processInfo.systemUptime
        // Center Stage follows your face and body on every frame, inside the app (a big share of the
        // camera's CPU); a little selfie bubble doesn't need it, so Dots turns it off for itself.
        AVCaptureDevice.centerStageControlMode = .app
        AVCaptureDevice.isCenterStageEnabled = false
        applyInputs()
        isConfigured = true
        Log.camera.debug("Configured in \(Log.ms(since: startedAt), format: .fixed(precision: 1)) ms")
    }

    private func devicesChanged(_ note: Notification, connected: Bool) {
        let name = (note.object as? AVCaptureDevice)?.localizedName ?? "A device"
        Log.camera.info("\(name, privacy: .public) was \(connected ? "connected" : "disconnected")")
        DispatchQueue.main.async { self.onDevicesChange?() }
        queue.async { if self.isConfigured { self.applyInputs() } }
    }

    /// Puts the chosen camera and microphone (or what stands in for them) on the session, leaving
    /// inputs that are already right alone.
    private func applyInputs() {
        let camera = Self.camera(id: cameraID)
        let microphone = Self.microphone(id: microphoneID)
        let oldCamera = input(for: .video)?.device.uniqueID
        let cameraChanges = oldCamera != camera?.uniqueID

        session.beginConfiguration()
        // Not every camera has 720p; .high fits any while the input swaps.
        if cameraChanges { session.sessionPreset = .high }
        let hasCamera = replaceInput(for: .video, with: camera)
        // 720p: plenty for even the biggest bubble (640 px wide on Retina), and half 1080p's pixels.
        session.sessionPreset = session.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .high
        let hasMicrophone = replaceInput(for: .audio, with: microphone)
        let isMetering = session.outputs.contains(audio)
        if hasMicrophone, !isMetering, session.canAddOutput(audio) {
            session.addOutput(audio)
        } else if !hasMicrophone, isMetering {
            session.removeOutput(audio)
        }
        session.commitConfiguration()
        // The tracker's frames keep the new camera's aspect.
        if cameraChanges, session.outputs.contains(frames) { frames.videoSettings = trackingSettings() }

        if !hasCamera { Log.camera.error("No usable camera found") }
        if !hasMicrophone { DispatchQueue.main.async { self.onVoiceLevel?(0) } }
        if cameraChanges {
            Log.camera.debug("Camera: \(camera?.localizedName ?? "none", privacy: .public)")
            DispatchQueue.main.async { self.onCameraChange?() }
        }
        Log.camera.debug("Microphone: \(microphone?.localizedName ?? "none", privacy: .public)")
    }

    /// Swaps the session's input of a media type for `device` (nil removes it). Whether the session
    /// ends up with one.
    private func replaceInput(for type: AVMediaType, with device: AVCaptureDevice?) -> Bool {
        let old = input(for: type)
        if let old, old.device.uniqueID == device?.uniqueID { return true }
        if let old { session.removeInput(old) }
        guard let device else { return false }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                Log.camera.error("Can't add \(device.localizedName, privacy: .public) to the session")
                return false
            }
            session.addInput(input)
            return true
        } catch {
            Log.camera.error("Can't open \(device.localizedName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func input(for type: AVMediaType) -> AVCaptureDeviceInput? {
        session.inputs.lazy.compactMap { $0 as? AVCaptureDeviceInput }.first { $0.device.hasMediaType(type) }
    }
}

/// The microphone's loudness from its channels' average power: a quiet room to speaking up close
/// maps to 0…1, rising at once and falling off gently, handed on ~30 times a second.
private final class VoiceMeter: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    var onLevel: ((CGFloat) -> Void)?
    private var level: CGFloat = 0
    private var lastSent: TimeInterval = 0

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let power = connection.audioChannels.map(\.averagePowerLevel).max() else { return } // dB, 0 is full scale
        let target = CGFloat(min(max((power + 50) / 35, 0), 1)) // −50 dB → 0, −15 dB → 1
        level = target > level ? target : level * 0.85 + target * 0.15
        let now = CACurrentMediaTime()
        guard now - lastSent >= 1.0 / 30 else { return }
        lastSent = now
        let level = level
        DispatchQueue.main.async { self.onLevel?(level) }
    }
}
