import Combine
import CoreGraphics
import Foundation

enum DotID: String, Codable, CaseIterable, Hashable, Identifiable {
    case mirror
    case tasks
    case redPen
    case screenToText
    case clipboard

    var id: String { rawValue }
}

enum DotPresentation: String, Codable, Equatable {
    case panel
    case overlay
    case directAction
}

enum AppPermission: String, Codable, Hashable {
    case camera
    case microphone
    case speechRecognition
    case screenRecording
    case notifications
}

struct DotDescriptor: Identifiable, Equatable {
    let id: DotID
    let title: String
    let presentation: DotPresentation
    let requiredPermissions: Set<AppPermission>
    let isImplemented: Bool
}

enum DotRegistry {
    static let maximumVisibleDots = 5
    static let defaultActiveIDs: [DotID] = [
        .mirror,
        .tasks,
        .redPen,
        .screenToText,
        .clipboard,
    ]

    static let catalog: [DotDescriptor] = [
        DotDescriptor(
            id: .mirror,
            title: "Mirror",
            presentation: .panel,
            requiredPermissions: [.camera],
            isImplemented: true
        ),
        DotDescriptor(
            id: .tasks,
            title: "Tasks",
            presentation: .panel,
            requiredPermissions: [],
            isImplemented: true
        ),
        DotDescriptor(
            id: .redPen,
            title: "Red Pen",
            presentation: .overlay,
            requiredPermissions: [],
            isImplemented: true
        ),
        DotDescriptor(
            id: .screenToText,
            title: "Screen to Text",
            presentation: .directAction,
            requiredPermissions: [.screenRecording],
            isImplemented: true
        ),
        DotDescriptor(
            id: .clipboard,
            title: "Clipboard",
            presentation: .panel,
            requiredPermissions: [],
            isImplemented: true
        ),
    ]

    static var implementedIDs: Set<DotID> {
        Set(catalog.lazy.filter(\.isImplemented).map(\.id))
    }

    static func descriptor(for id: DotID) -> DotDescriptor? {
        catalog.first { $0.id == id }
    }

    static func descriptors(for ids: [DotID]) -> [DotDescriptor] {
        ids.compactMap(descriptor(for:))
    }

    static func visibleIDs(
        from requested: [DotID],
        implemented: Set<DotID> = implementedIDs
    ) -> [DotID] {
        var seen = Set<DotID>()
        let visible = requested.compactMap { id -> DotID? in
            guard implemented.contains(id), seen.insert(id).inserted else { return nil }
            return id
        }
        .prefix(maximumVisibleDots)

        if visible.isEmpty {
            return defaultActiveIDs.filter(implemented.contains)
        }
        return Array(visible)
    }
}

@MainActor
final class LauncherPointerState: ObservableObject {
    @Published private(set) var location: CGPoint?
    @Published private(set) var activationSequence = 0
    @Published private(set) var dismissalSequence = 0
    @Published private(set) var cameraOffset: CGSize = .zero
    @Published private(set) var cameraReveal = false
    @Published private(set) var cameraMaskFrame: CGRect?
    private(set) var requestedActivation: DotID?
    private var lastActivationAt: TimeInterval = 0

    func update(_ location: CGPoint?) {
        guard self.location != location else { return }
        self.location = location
    }

    func requestActivation(of id: DotID, ignoreDebounce: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        if !ignoreDebounce, requestedActivation == id, now - lastActivationAt < 0.18 {
            return
        }
        lastActivationAt = now
        requestedActivation = id
        activationSequence &+= 1
    }

    func requestDismissal() {
        requestedActivation = nil
        dismissalSequence &+= 1
    }

    func setCameraOffset(_ offset: CGSize) {
        guard cameraOffset != offset else { return }
        cameraOffset = offset
    }

    func setCameraReveal(_ revealed: Bool) {
        guard cameraReveal != revealed else { return }
        cameraReveal = revealed
    }

    func setCameraMaskFrame(_ frame: CGRect?) {
        guard cameraMaskFrame != frame else { return }
        cameraMaskFrame = frame
    }
}

enum DotMagnetism {
    static let activationRadius: CGFloat = 64
    static let maximumOffset: CGFloat = 8

    static func offsets(
        pointer: CGPoint?,
        anchors: [CGPoint],
        activationRadius: CGFloat = activationRadius,
        maximumOffset: CGFloat = maximumOffset
    ) -> [CGSize] {
        var result = Array(repeating: CGSize.zero, count: anchors.count)
        guard let pointer, !anchors.isEmpty, activationRadius > 0, maximumOffset > 0 else {
            return result
        }

        let nearest = anchors.enumerated().min { lhs, rhs in
            squaredDistance(from: pointer, to: lhs.element)
                < squaredDistance(from: pointer, to: rhs.element)
        }
        guard let nearest else { return result }

        let dx = pointer.x - nearest.element.x
        let dy = pointer.y - nearest.element.y
        let distance = sqrt((dx * dx) + (dy * dy))
        guard distance > 0, distance < activationRadius else { return result }

        let strength = 1 - (distance / activationRadius)
        let travel = min(distance, maximumOffset) * strength
        result[nearest.offset] = CGSize(
            width: (dx / distance) * travel,
            height: (dy / distance) * travel
        )
        return result
    }

    private static func squaredDistance(from point: CGPoint, to anchor: CGPoint) -> CGFloat {
        let dx = point.x - anchor.x
        let dy = point.y - anchor.y
        return (dx * dx) + (dy * dy)
    }
}
