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

struct CameraGeneration: Equatable {
    private(set) var token: UInt64 = 0
    private(set) var wantsToRun = false

    mutating func start() -> UInt64 {
        token += 1
        wantsToRun = true
        return token
    }

    mutating func stop() -> UInt64 {
        token += 1
        wantsToRun = false
        return token
    }

    func isCurrent(_ candidate: UInt64) -> Bool {
        candidate == token
    }
}

enum CameraPreviewPreset {
    static let candidates: [AVCaptureSession.Preset] = [
        .vga640x480,
        .medium,
        .cif352x288,
        .low,
        .high,
    ]

    static func preferred(canSet: (AVCaptureSession.Preset) -> Bool) -> AVCaptureSession.Preset {
        candidates.first(where: canSet) ?? .high
    }
}

enum CameraRuntimeErrorPolicy {
    /// `AVErrorMediaServicesWereReset`; not exposed as `AVError.Code` on macOS.
    static let mediaServicesWereResetCode = -11819

    static func isMediaServicesReset(_ error: Error?) -> Bool {
        let nsError = error as NSError?
        return nsError?.domain == AVFoundationErrorDomain
            && nsError?.code == mediaServicesWereResetCode
    }

    static func shouldRetry(alreadyRetried: Bool, error: Error?) -> Bool {
        !alreadyRetried && isMediaServicesReset(error)
    }
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
    private var generation = CameraGeneration()
    private var isConfigured = false
    private var retriedMediaResetToken: UInt64?
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
        let token = beginStart()

        switch CameraAuthorization.action(for: AVCaptureDevice.authorizationStatus(for: .video)) {
        case .start:
            publish(.starting, token: token)
            startSessionOnQueue(token: token)
        case .requestAccess:
            publish(.requestingPermission, token: token)
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self, self.isCurrent(token) else { return }
                if granted, self.shouldRun {
                    self.publish(.starting, token: token)
                    self.startSessionOnQueue(token: token)
                } else {
                    self.publish(granted ? .idle : .denied, token: token)
                }
            }
        case .denied:
            publish(.denied, token: token)
        case .failed:
            publish(.failed, token: token)
        }
    }

    func stop() {
        let token = beginStop()
        sessionQueue.async { [weak self] in
            guard let self, self.isCurrent(token) else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.publish(.idle, token: token)
        }
    }

    private func startSessionOnQueue(token: UInt64) {
        sessionQueue.async { [weak self] in
            self?.runSessionIfNeeded(token: token)
        }
    }

    private func runSessionIfNeeded(token: UInt64) {
        guard isCurrent(token), shouldRun else { return }

        do {
            try configureIfNeeded()
            guard isCurrent(token), shouldRun else { return }
            if !session.isRunning {
                session.startRunning()
            }
            guard isCurrent(token), shouldRun else {
                if session.isRunning {
                    session.stopRunning()
                }
                return
            }
            publish(.running, token: token)
        } catch CameraError.noDevice {
            publish(.unavailable, token: token)
        } catch {
            publish(.failed, token: token)
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

        guard session.canAddInput(input) else {
            throw CameraError.cannotAddInput
        }

        session.addInput(input)
        session.sessionPreset = CameraPreviewPreset.preferred(canSet: session.canSetSessionPreset)
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
            ) { [weak self] notification in
                let error = notification.userInfo?[AVCaptureSessionErrorKey] as? Error
                self?.sessionQueue.async {
                    guard let self else { return }
                    let token = self.currentToken()
                    guard self.isCurrent(token), self.shouldRun else { return }
                    self.resetConfiguration()
                    if CameraRuntimeErrorPolicy.shouldRetry(
                        alreadyRetried: self.retriedMediaResetToken == token,
                        error: error
                    ) {
                        self.retriedMediaResetToken = token
                        self.publish(.starting, token: token)
                        self.runSessionIfNeeded(token: token)
                    } else {
                        self.publish(.failed, token: token)
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
                    guard let self else { return }
                    let token = self.currentToken()
                    guard self.isCurrent(token), self.shouldRun else { return }
                    self.publish(.failed, token: token)
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
                    guard let self else { return }
                    let token = self.currentToken()
                    guard self.isCurrent(token), self.shouldRun else { return }
                    if self.session.isRunning {
                        self.publish(.running, token: token)
                    } else {
                        self.publish(.starting, token: token)
                        self.runSessionIfNeeded(token: token)
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
                    let token = self.currentToken()
                    let usesDevice = self.session.inputs.contains { input in
                        (input as? AVCaptureDeviceInput)?.device.uniqueID == device.uniqueID
                    }
                    guard usesDevice else { return }

                    if self.session.isRunning {
                        self.session.stopRunning()
                    }
                    self.resetConfiguration()

                    guard self.isCurrent(token) else { return }
                    if self.shouldRun {
                        self.publish(.starting, token: token)
                        self.runSessionIfNeeded(token: token)
                    } else {
                        self.publish(.idle, token: token)
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
        return generation.wantsToRun
    }

    private func beginStart() -> UInt64 {
        requestLock.lock()
        defer { requestLock.unlock() }
        return generation.start()
    }

    private func beginStop() -> UInt64 {
        requestLock.lock()
        defer { requestLock.unlock() }
        return generation.stop()
    }

    private func currentToken() -> UInt64 {
        requestLock.lock()
        defer { requestLock.unlock() }
        return generation.token
    }

    private func isCurrent(_ token: UInt64) -> Bool {
        requestLock.lock()
        defer { requestLock.unlock() }
        return generation.isCurrent(token)
    }

    private func publish(_ newStatus: Status, token: UInt64) {
        guard isCurrent(token) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isCurrent(token) else { return }
            self.status = newStatus
        }
    }
}

private enum CameraError: Error {
    case noDevice
    case cannotAddInput
}
