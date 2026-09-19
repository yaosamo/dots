import AVFoundation
import SwiftUI

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> CameraPreviewView {
        CameraPreviewView(session: session)
    }

    func updateNSView(_ nsView: CameraPreviewView, context: Context) {
        nsView.previewLayer.session = session
        nsView.applyMirroring()
    }
}

final class CameraPreviewView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()
    private var startObserver: NSObjectProtocol?

    init(session: AVCaptureSession) {
        super.init(frame: .zero)
        wantsLayer = true
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        layer = previewLayer
        applyMirroring()

        startObserver = NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionDidStartRunning,
            object: session,
            queue: .main
        ) { [weak self] _ in
            self?.applyMirroring()
        }
    }

    deinit {
        if let startObserver {
            NotificationCenter.default.removeObserver(startObserver)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
        applyMirroring()
    }

    func applyMirroring() {
        guard let connection = previewLayer.connection, connection.isVideoMirroringSupported else {
            return
        }

        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = true
    }
}
