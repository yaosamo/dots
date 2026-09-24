import AVFoundation

/// Owns the capture session; all session work happens on a private serial queue.
final class CameraSession {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "app.dots.camera")
    private var isConfigured = false
    private var observers: [NSObjectProtocol] = []

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
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
            ?? AVCaptureDevice.default(for: .video)
        guard let device, let input = try? AVCaptureDeviceInput(device: device) else {
            Log.camera.error("No usable camera found")
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .high
        if session.canAddInput(input) { session.addInput(input) }
        session.commitConfiguration()
        isConfigured = true
        Log.camera.debug("Configured \(device.localizedName, privacy: .public) in \(Log.ms(since: startedAt), format: .fixed(precision: 1)) ms")
    }
}
