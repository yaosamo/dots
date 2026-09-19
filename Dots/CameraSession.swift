import AppKit
import AVFoundation
import Combine

enum CameraAuthorizationAction: Equatable {
    case start
    case requestAccess
    case denied
    case failed
}

enum CameraAuthorization {
    static func action(for status: AVAuthorizationStatus) -> CameraAuthorizationAction {
        switch status {
        case .authorized:
            return .start
        case .notDetermined:
            return .requestAccess
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .failed
        }
    }
}

enum CameraDeviceKind: Equatable {
    case builtInWideAngle
    case continuity
    case external
    case other
}

struct CameraDeviceCandidate: Equatable {
    var uniqueID: String
    var kind: CameraDeviceKind
    var position: AVCaptureDevice.Position
}

enum CameraDevicePicker {
    static func preferred(from candidates: [CameraDeviceCandidate]) -> CameraDeviceCandidate? {
        candidates.min { rank($0) < rank($1) }
    }

    static func rank(_ candidate: CameraDeviceCandidate) -> Int {
        switch candidate.kind {
        case .builtInWideAngle:
            switch candidate.position {
            case .front:
                return 0
            case .unspecified:
                return 1
            case .back:
                return 2
            @unknown default:
                return 3
            }
        case .continuity:
            return 10
        case .external:
            return 20
        case .other:
            return 30
        }
    }
}

enum CameraStatusOverlay: Equatable {
    case none
    case spinner
    case unavailable
}

final class CameraSession: ObservableObject {
    enum Status: Equatable {
        case idle
        case requestingPermission
        case starting
        case running
        case denied
        case unavailable
        case failed

        var overlay: CameraStatusOverlay {
            switch self {
            case .idle, .running:
                return .none
            case .requestingPermission, .starting:
                return .spinner
            case .denied, .unavailable, .failed:
                return .unavailable
            }
        }

        var accessibilityDescription: String {
            switch self {
            case .idle:
                return "Camera inactive"
            case .requestingPermission:
                return "Waiting for camera permission"
            case .starting:
                return "Starting camera"
            case .running:
                return "Camera active"
            case .denied:
                return "Camera permission denied"
            case .unavailable:
                return "No camera available"
            case .failed:
                return "Camera unavailable"
            }
        }
    }

    let session = AVCaptureSession()

    @Published private(set) var status: Status = .idle

    private let sessionQueue = DispatchQueue(label: "com.yaosamo.Dots.camera-session")
    private let requestLock = NSLock()
    private var isConfigured = false
    private var wantsToRun = false
    private var observers: [NSObjectProtocol] = []

    var accessibilityDescription: String {
        status.accessibilityDescription
    }

    init() {
        observeLifecycle()
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        if session.isRunning {
            session.stopRunning()
        }
    }

    func start() {
        setWantsToRun(true)

        switch CameraAuthorization.action(for: AVCaptureDevice.authorizationStatus(for: .video)) {
        case .start:
            publish(.starting)
            startSessionOnQueue()
        case .requestAccess:
            publish(.requestingPermission)
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                if granted, self.shouldRun {
                    self.publish(.starting)
                    self.startSessionOnQueue()
                } else {
                    self.publish(granted ? .idle : .denied)
                }
            }
        case .denied:
            publish(.denied)
        case .failed:
            publish(.failed)
        }
    }

    func stop() {
        setWantsToRun(false)
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.publish(.idle)
        }
    }

    private func startSessionOnQueue() {
        sessionQueue.async { [weak self] in
            self?.runSessionIfNeeded()
        }
    }

    private func runSessionIfNeeded() {
        guard shouldRun else { return }

        do {
            try configureIfNeeded()
            guard shouldRun else { return }
            if !session.isRunning {
                session.startRunning()
            }
            publish(.running)
        } catch CameraError.noDevice {
            publish(.unavailable)
        } catch {
            publish(.failed)
        }
    }

    private func configureIfNeeded() throws {
        if isConfigured, session.inputs.isEmpty {
            isConfigured = false
        }

        guard !isConfigured else { return }
        guard let device = preferredDevice() else {
            throw CameraError.noDevice
        }

        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .high

        guard session.canAddInput(input) else {
            throw CameraError.cannotAddInput
        }

        session.addInput(input)
        isConfigured = true
    }

    private func resetConfiguration() {
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        session.commitConfiguration()
        isConfigured = false
    }

    private func preferredDevice() -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        let candidates = discovery.devices.map { device in
            CameraDeviceCandidate(
                uniqueID: device.uniqueID,
                kind: Self.kind(for: device),
                position: device.position
            )
        }

        if let pick = CameraDevicePicker.preferred(from: candidates),
           let device = AVCaptureDevice(uniqueID: pick.uniqueID) {
            return device
        }

        return AVCaptureDevice.default(for: .video)
    }

    private static func kind(for device: AVCaptureDevice) -> CameraDeviceKind {
        switch device.deviceType {
        case .builtInWideAngleCamera:
            return .builtInWideAngle
        case .continuityCamera:
            return .continuity
        case .external:
            return .external
        default:
            return .other
        }
    }

    private func observeLifecycle() {
        let center = NotificationCenter.default

        observers.append(
            center.addObserver(
                forName: .AVCaptureSessionRuntimeError,
                object: session,
                queue: nil
            ) { [weak self] _ in
                self?.sessionQueue.async {
                    guard let self else { return }
                    self.resetConfiguration()
                    if self.shouldRun {
                        self.publish(.failed)
                    }
                }
            }
        )

        observers.append(
            center.addObserver(
                forName: .AVCaptureSessionWasInterrupted,
                object: session,
                queue: nil
            ) { [weak self] _ in
                self?.sessionQueue.async {
                    guard let self, self.shouldRun else { return }
                    self.publish(.failed)
                }
            }
        )

        observers.append(
            center.addObserver(
                forName: .AVCaptureSessionInterruptionEnded,
                object: session,
                queue: nil
            ) { [weak self] _ in
                self?.sessionQueue.async {
                    guard let self, self.shouldRun else { return }
                    if self.session.isRunning {
                        self.publish(.running)
                    } else {
                        self.publish(.starting)
                        self.runSessionIfNeeded()
                    }
                }
            }
        )

        observers.append(
            center.addObserver(
                forName: .AVCaptureDeviceWasDisconnected,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                guard let device = notification.object as? AVCaptureDevice else { return }
                self?.sessionQueue.async {
                    guard let self else { return }
                    let usesDevice = self.session.inputs.contains { input in
                        (input as? AVCaptureDeviceInput)?.device.uniqueID == device.uniqueID
                    }
                    guard usesDevice else { return }

                    if self.session.isRunning {
                        self.session.stopRunning()
                    }
                    self.resetConfiguration()

                    if self.shouldRun {
                        self.publish(.starting)
                        self.runSessionIfNeeded()
                    } else {
                        self.publish(.idle)
                    }
                }
            }
        )

        observers.append(
            center.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.stop()
            }
        )
    }

    private var shouldRun: Bool {
        requestLock.lock()
        defer { requestLock.unlock() }
        return wantsToRun
    }

    private func setWantsToRun(_ value: Bool) {
        requestLock.lock()
        wantsToRun = value
        requestLock.unlock()
    }

    private func publish(_ newStatus: Status) {
        DispatchQueue.main.async { [weak self] in
            self?.status = newStatus
        }
    }
}

private enum CameraError: Error {
    case noDevice
    case cannotAddInput
}
