import AVFoundation

/// Owns the capture session; all session work happens on a private serial queue.
final class CameraSession {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.dots.camera")
    private var isConfigured = false
    private var observers: [NSObjectProtocol] = []
    /// Frames for the head tracker. Only attached to the session while tracking: attached, it has the
    /// camera deliver (and convert) every frame, which costs CPU even with no delegate.
    private let frames: AVCaptureVideoDataOutput = {
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        // The camera's own format, so frames aren't converted, and small: tracking a head or hand
        // needs no more, the camera scales them for free, and Vision has a quarter of 720p to look at.
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            kCVPixelBufferWidthKey as String: 640,
            kCVPixelBufferHeightKey as String: 360,
        ]
        return output
    }()
    private let framesQueue = DispatchQueue(label: "app.dots.camera.frames", qos: .userInitiated)

    init() {
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
        ]
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
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
            ?? AVCaptureDevice.default(for: .video)
        guard let device, let input = try? AVCaptureDeviceInput(device: device) else {
            Log.camera.error("No usable camera found")
            return
        }

        session.beginConfiguration()
        // 720p: plenty for even the biggest bubble (640 px wide on Retina), and half 1080p's pixels.
        session.sessionPreset = session.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .high
        if session.canAddInput(input) { session.addInput(input) }
        session.commitConfiguration()
        isConfigured = true
        Log.camera.debug("Configured \(device.localizedName, privacy: .public) in \(Log.ms(since: startedAt), format: .fixed(precision: 1)) ms")
    }
}
