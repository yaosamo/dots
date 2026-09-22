import AppKit
import SwiftUI

enum DotExpansion: Equatable {
    case none
    case camera
    case tasks
    case clipboard
    case redPen
    case screenToText
}

enum DotMaterialStyle: String, CaseIterable, Codable, Identifiable {
    case liquid
    case regular
    case thin
    case solid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .liquid:
            return "Liquid"
        case .regular:
            return "Regular"
        case .thin:
            return "Thin"
        case .solid:
            return "Solid"
        }
    }
}

final class DotAppearanceSettings: ObservableObject {
    static let shared = DotAppearanceSettings()
    static let materialKey = "dot.material"

    @Published var material: DotMaterialStyle {
        didSet {
            defaults.set(material.rawValue, forKey: Self.materialKey)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedMaterial = defaults.string(forKey: Self.materialKey)
            .flatMap(DotMaterialStyle.init(rawValue:))
        material = storedMaterial ?? .liquid
    }
}

struct DotOrbMaterialView: View {
    let style: DotMaterialStyle

    @ViewBuilder
    var body: some View {
        switch style {
        case .liquid:
            if #available(macOS 26.0, *) {
                Circle()
                    .fill(.black.opacity(0.2))
                    .glassEffect(
                        .regular.tint(.black.opacity(0.76)),
                        in: Circle()
                    )
                    .overlay {
                        Circle().stroke(.white.opacity(0.2), lineWidth: 0.5)
                    }
            } else {
                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay {
                        Circle().fill(.black.opacity(0.55))
                    }
                    .overlay {
                        Circle().stroke(.white.opacity(0.2), lineWidth: 0.5)
                    }
            }
        case .regular:
            Circle()
                .fill(.regularMaterial)
                .overlay {
                    Circle().stroke(.white.opacity(0.2), lineWidth: 0.5)
                }
        case .thin:
            Circle()
                .fill(.thinMaterial)
                .overlay {
                    Circle().stroke(.white.opacity(0.2), lineWidth: 0.5)
                }
        case .solid:
            Circle().fill(.black)
        }
    }
}

enum CameraPanelStyle: Equatable {
    case rectangle
    case circle

    static let transitionDuration: TimeInterval = 0.2

    var size: CGSize {
        size(for: .standard)
    }

    func size(for sizeMode: CameraPanelSize) -> CGSize {
        let width: CGFloat = sizeMode == .standard ? 240 : 160

        switch self {
        case .rectangle:
            return CGSize(width: width, height: width * 1.5)
        case .circle:
            return CGSize(width: width, height: width)
        }
    }

    var panelSize: CGSize {
        size
    }

    func panelSize(for sizeMode: CameraPanelSize) -> CGSize {
        size(for: sizeMode)
    }

    var surfaceAspectRatio: CGFloat {
        size.width / size.height
    }

    var minimumSurfaceSize: CGSize {
        minimumSurfaceSize(for: .standard)
    }

    func minimumSurfaceSize(for sizeMode: CameraPanelSize) -> CGSize {
        let size = size(for: sizeMode)
        return CGSize(
            width: size.width,
            height: size.height
        )
    }

    var minimumPanelSize: CGSize {
        minimumSurfaceSize
    }

    func minimumPanelSize(for sizeMode: CameraPanelSize) -> CGSize {
        minimumSurfaceSize(for: sizeMode)
    }

    var nextSymbolName: String {
        switch self {
        case .rectangle:
            return "circle"
        case .circle:
            return "rectangle"
        }
    }

    var toggleAccessibilityLabel: String {
        switch self {
        case .rectangle:
            return "Use circular camera"
        case .circle:
            return "Use rectangular camera"
        }
    }
}

enum CameraPanelSize: Equatable {
    case standard
    case small

    var nextSymbolName: String {
        switch self {
        case .standard:
            return "arrow.down.right.and.arrow.up.left"
        case .small:
            return "arrow.up.left.and.arrow.down.right"
        }
    }

    var toggleAccessibilityLabel: String {
        switch self {
        case .standard:
            return "Use smaller camera"
        case .small:
            return "Use full-size camera"
        }
    }
}

@MainActor
final class CameraPanelModel: ObservableObject {
    @Published var style: CameraPanelStyle = .circle
    @Published var sizeMode: CameraPanelSize = .standard
    @Published var isTransitioning = false

    func toggleStyle() {
        style = style == .circle ? .rectangle : .circle
    }

    func toggleSize() {
        sizeMode = sizeMode == .standard ? .small : .standard
    }

    func resetStyle() {
        style = .circle
        sizeMode = .standard
        isTransitioning = false
    }
}

enum DotsLayout {
    static let nodeDiameter: CGFloat = 16
    static let cameraDiameter: CGFloat = 160
    static let cameraPanelSize = CameraPanelStyle.circle.size
    static let cameraPanelGap: CGFloat = 16
    static let cameraPanelCornerRadius: CGFloat = 18
    static let launchCadence: TimeInterval = 0.08
    static let nodeSpacing: CGFloat = 16
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 8
    static let dotHitSlop: CGFloat = 12
    static let cameraControlSize: CGFloat = 32
    static let cameraControlGap: CGFloat = 8
    static let cameraControlEdgePadding: CGFloat = 16
    static let cameraControlStackHeight =
        (cameraControlSize * 3) + (cameraControlGap * 2) + cameraControlEdgePadding
    static let cameraMinimumSurfaceWidth: CGFloat = 240
    static let hangingGap: CGFloat = 8
    static let taskListWidth: CGFloat = 434
    static let taskRowHeight: CGFloat = 51
    static let taskFontSize: CGFloat = 16
    static let taskRowSpacing: CGFloat = 6
    static let taskEditingTextVerticalOffset: CGFloat = 1
    static let taskContentLeadingPadding: CGFloat = 12
    static let taskContentTrailingPadding: CGFloat = 16
    static let taskPanelPadding: CGFloat = 16
    static let taskMaximumVisibleRows = 6
    static let taskCornerRadius: CGFloat = 18
    static let taskCanvasEnvelope = CGSize(width: 480, height: 506)
    static let clipboardCornerRadius: CGFloat = 12
    static let taskControlHitSize: CGFloat = 24
    static let clipboardSize = CGSize(width: 240, height: 220)
    static let glassInset: CGFloat = 12

    static func taskListContentSize(taskCount: Int) -> CGSize {
        let rowCount = min(max(taskCount + 1, 1), taskMaximumVisibleRows)
        return CGSize(
            width: taskListWidth,
            height: (taskRowHeight * CGFloat(rowCount))
                + (taskRowSpacing * CGFloat(rowCount - 1))
        )
    }

    static func taskListSize(taskCount: Int) -> CGSize {
        let contentSize = taskListContentSize(taskCount: taskCount)
        return CGSize(
            width: contentSize.width + (taskPanelPadding * 2),
            height: contentSize.height + (taskPanelPadding * 2)
        )
    }

    static var rowContentSize: CGSize {
        rowContentSize(dotCount: DotRegistry.defaultActiveIDs.count)
    }

    static func rowContentSize(dotCount: Int) -> CGSize {
        let count = min(max(dotCount, 1), DotRegistry.maximumVisibleDots)
        return CGSize(
            width: (nodeDiameter * CGFloat(count))
                + (nodeSpacing * CGFloat(max(0, count - 1))),
            height: nodeDiameter
        )
    }

    static var rowPanelSize: CGSize {
        rowPanelSize(dotCount: DotRegistry.defaultActiveIDs.count)
    }

    static func rowPanelSize(dotCount: Int) -> CGSize {
        let content = rowContentSize(dotCount: dotCount)
        return CGSize(
            width: content.width + (horizontalPadding * 2),
            height: content.height + (verticalPadding * 2)
        )
    }

    static var rowCenterX: CGFloat {
        rowCenterX(cameraOffset: .zero)
    }

    static var canvasSize: CGSize {
        canvasSize(cameraOffset: .zero)
    }

    static var dotHitDiameter: CGFloat {
        nodeDiameter + (dotHitSlop * 2)
    }

    static func cameraPanelFrame(
        anchoredTo anchor: CGRect,
        style: CameraPanelStyle = .circle,
        sizeMode: CameraPanelSize = .standard
    ) -> CGRect {
        let size = style.panelSize(for: sizeMode)
        return CGRect(
            x: anchor.midX - (size.width / 2),
            y: anchor.minY - cameraPanelGap - size.height,
            width: size.width,
            height: size.height
        )
    }

    static func cameraPanelResizeFrame(
        from currentFrame: CGRect,
        to size: CGSize
    ) -> CGRect {
        CGRect(
            x: currentFrame.midX - (size.width / 2),
            y: currentFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    static func extraLeft(
        cameraOffset: CGSize,
        dotIDs: [DotID] = DotRegistry.defaultActiveIDs
    ) -> CGFloat {
        guard let hang = rawHangingFrame(
            expansion: .camera,
            cameraOffset: cameraOffset,
            taskCount: 0,
            dotIDs: dotIDs
        ) else {
            return 0
        }
        return max(0, -(hang.minX + baseLayoutOffsetX(dotIDs: dotIDs)))
    }

    static func rowCenterX(
        cameraOffset: CGSize,
        dotIDs: [DotID] = DotRegistry.defaultActiveIDs
    ) -> CGFloat {
        baseLayoutOffsetX(dotIDs: dotIDs)
            + extraLeft(cameraOffset: cameraOffset, dotIDs: dotIDs)
            + (rowPanelSize(dotCount: normalized(dotIDs).count).width / 2)
    }

    static func canvasSize(
        cameraOffset: CGSize,
        dotIDs: [DotID] = DotRegistry.defaultActiveIDs
    ) -> CGSize {
        let base = baseCanvasSize(dotIDs: dotIDs)
        guard let hang = hangingFrame(
            expansion: .camera,
            cameraOffset: cameraOffset,
            dotIDs: dotIDs
        ) else {
            return base
        }
        return CGSize(
            width: max(
                base.width + extraLeft(cameraOffset: cameraOffset, dotIDs: dotIDs),
                hang.maxX + glassInset
            ),
            height: max(base.height, hang.maxY + glassInset)
        )
    }

    static func nodeFrames(
        expansion: DotExpansion,
        cameraOffset: CGSize = .zero,
        dotIDs: [DotID] = DotRegistry.defaultActiveIDs
    ) -> [CGRect] {
        let offsetX = baseLayoutOffsetX(dotIDs: dotIDs)
            + extraLeft(cameraOffset: cameraOffset, dotIDs: dotIDs)
        return rawNodeFrames(dotIDs: dotIDs).map {
            $0.offsetBy(dx: offsetX, dy: 0)
        }
    }

    static func visibleNodeFrames(
        expansion: DotExpansion,
        cameraOffset: CGSize = .zero,
        dotIDs: [DotID] = DotRegistry.defaultActiveIDs
    ) -> [CGRect] {
        nodeFrames(
            expansion: expansion,
            cameraOffset: cameraOffset,
            dotIDs: dotIDs
        )
    }

    static func hangingFrame(
        expansion: DotExpansion,
        cameraOffset: CGSize = .zero,
        taskCount: Int = 0,
        dotIDs: [DotID] = DotRegistry.defaultActiveIDs
    ) -> CGRect? {
        rawHangingFrame(
            expansion: expansion,
            cameraOffset: cameraOffset,
            taskCount: taskCount,
            dotIDs: dotIDs
        )?.offsetBy(
            dx: baseLayoutOffsetX(dotIDs: dotIDs)
                + extraLeft(cameraOffset: cameraOffset, dotIDs: dotIDs),
            dy: 0
        )
    }

    static func containsInteractiveContent(
        _ point: CGPoint,
        expansion: DotExpansion,
        cameraOffset: CGSize = .zero,
        taskCount: Int = 0,
        dotIDs: [DotID] = DotRegistry.defaultActiveIDs
    ) -> Bool {
        if dotID(
            at: point,
            expansion: expansion,
            cameraOffset: cameraOffset,
            dotIDs: dotIDs
        ) != nil {
            return true
        }

        if let hang = hangingFrame(
            expansion: expansion,
            cameraOffset: cameraOffset,
            taskCount: taskCount,
            dotIDs: dotIDs
        ) {
            switch expansion {
            case .camera:
                if circleContains(hang, point) { return true }
            case .tasks, .clipboard:
                if roundedRectContains(hang, radius: taskCornerRadius, point: point) {
                    return true
                }
            case .none, .redPen, .screenToText:
                break
            }
        }

        return false
    }

    static func dotID(
        at point: CGPoint,
        expansion: DotExpansion,
        cameraOffset: CGSize = .zero,
        dotIDs: [DotID] = DotRegistry.defaultActiveIDs
    ) -> DotID? {
        let ids = normalized(dotIDs)
        let frames = nodeFrames(
            expansion: expansion,
            cameraOffset: cameraOffset,
            dotIDs: ids
        )
        var nearestID: DotID?
        var nearestDistance = CGFloat.infinity
        for index in ids.indices {
            let dotTarget = frames[index].insetBy(dx: -dotHitSlop, dy: -dotHitSlop)
            guard circleContains(dotTarget, point) else { continue }

            let dx = point.x - frames[index].midX
            let dy = point.y - frames[index].midY
            let distance = (dx * dx) + (dy * dy)
            if distance < nearestDistance {
                nearestID = ids[index]
                nearestDistance = distance
            }
        }
        return nearestID
    }

    static func panelFrame(
        visibleFrame: CGRect,
        cameraOffset: CGSize = .zero,
        previousCameraOffset: CGSize = .zero,
        keepingTopOf existingFrame: CGRect? = nil,
        dotIDs: [DotID] = DotRegistry.defaultActiveIDs
    ) -> CGRect {
        let size = canvasSize(cameraOffset: cameraOffset, dotIDs: dotIDs)
        let rowCenter = rowCenterX(cameraOffset: cameraOffset, dotIDs: dotIDs)
        if let existingFrame {
            let previousRowCenter = rowCenterX(
                cameraOffset: previousCameraOffset,
                dotIDs: dotIDs
            )
            return CGRect(
                x: existingFrame.minX + previousRowCenter - rowCenter,
                y: existingFrame.maxY - size.height,
                width: size.width,
                height: size.height
            )
        }
        return CGRect(
            x: visibleFrame.midX - rowCenter,
            y: visibleFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    static func launchStartFrame(docked: CGRect, canvasHeight: CGFloat) -> CGRect {
        CGRect(
            x: docked.minX,
            y: canvasHeight + nodeDiameter,
            width: docked.width,
            height: docked.height
        )
    }

    private static func normalized(_ dotIDs: [DotID]) -> [DotID] {
        DotRegistry.visibleIDs(from: dotIDs, implemented: Set(DotID.allCases))
    }

    private static func rawNodeFrames(dotIDs: [DotID]) -> [CGRect] {
        var x = horizontalPadding
        return normalized(dotIDs).map { _ in
            defer { x += nodeDiameter + nodeSpacing }
            return CGRect(
                x: x,
                y: verticalPadding,
                width: nodeDiameter,
                height: nodeDiameter
            )
        }
    }

    private static func baseLayoutOffsetX(dotIDs: [DotID]) -> CGFloat {
        glassInset - staticBounds(dotIDs: dotIDs).minX
    }

    private static func baseCanvasSize(dotIDs: [DotID]) -> CGSize {
        let bounds = staticBounds(dotIDs: dotIDs)
        return CGSize(
            width: bounds.width + (glassInset * 2),
            height: bounds.maxY + glassInset
        )
    }

    private static func staticBounds(dotIDs: [DotID]) -> CGRect {
        let ids = normalized(dotIDs)
        var bounds = CGRect(origin: .zero, size: rowPanelSize(dotCount: ids.count))
        if ids.contains(.tasks) {
            let taskCenterX = rowPanelSize(dotCount: ids.count).width / 2
            bounds = bounds.union(
                CGRect(
                    x: taskCenterX - (taskCanvasEnvelope.width / 2),
                    y: verticalPadding + nodeDiameter + hangingGap,
                    width: taskCanvasEnvelope.width,
                    height: taskCanvasEnvelope.height
                )
            )
        }
        for expansion in [DotExpansion.camera, .tasks, .clipboard] {
            if let frame = rawHangingFrame(
                expansion: expansion,
                cameraOffset: .zero,
                taskCount: 100,
                dotIDs: ids
            ) {
                bounds = bounds.union(frame)
            }
        }
        return bounds
    }

    private static func rawHangingFrame(
        expansion: DotExpansion,
        cameraOffset: CGSize,
        taskCount: Int,
        dotIDs: [DotID]
    ) -> CGRect? {
        let ids = normalized(dotIDs)
        guard let index = activeNodeIndex(expansion: expansion, dotIDs: ids) else {
            return nil
        }
        let dot = rawNodeFrames(dotIDs: ids)[index]

        switch expansion {
        case .none:
            return nil
        case .camera:
            var frame = CGRect(
                x: dot.midX - (cameraDiameter / 2),
                y: dot.maxY,
                width: cameraDiameter,
                height: cameraDiameter
            )
            frame = frame.offsetBy(dx: cameraOffset.width, dy: cameraOffset.height)
            if frame.minY < 0 {
                frame.origin.y = 0
            }
            return frame
        case .tasks:
            let size = taskListSize(taskCount: taskCount)
            let taskCenterX = rowPanelSize(dotCount: ids.count).width / 2
            return CGRect(
                x: taskCenterX - (size.width / 2),
                y: dot.maxY + hangingGap,
                width: size.width,
                height: size.height
            )
        case .clipboard:
            return CGRect(
                x: dot.midX - (clipboardSize.width / 2),
                y: dot.maxY + hangingGap,
                width: clipboardSize.width,
                height: clipboardSize.height
            )
        case .redPen, .screenToText:
            return nil
        }
    }

    private static func activeNodeIndex(
        expansion: DotExpansion,
        dotIDs: [DotID]
    ) -> Int? {
        let id: DotID?
        switch expansion {
        case .none:
            id = nil
        case .camera:
            id = .mirror
        case .tasks:
            id = .tasks
        case .clipboard:
            id = .clipboard
        case .redPen:
            id = .redPen
        case .screenToText:
            id = .screenToText
        }
        return id.flatMap { normalized(dotIDs).firstIndex(of: $0) }
    }

    private static func circleContains(_ rect: CGRect, _ point: CGPoint) -> Bool {
        let dx = point.x - rect.midX
        let dy = point.y - rect.midY
        let radius = min(rect.width, rect.height) / 2
        return (dx * dx) + (dy * dy) <= (radius * radius)
    }

    private static func roundedRectContains(
        _ rect: CGRect,
        radius: CGFloat,
        point: CGPoint
    ) -> Bool {
        guard rect.contains(point) else { return false }

        let corner = min(radius, rect.width / 2, rect.height / 2)
        let inner = rect.insetBy(dx: corner, dy: corner)
        if point.x >= inner.minX, point.x <= inner.maxX { return true }
        if point.y >= inner.minY, point.y <= inner.maxY { return true }

        let corners = [
            CGPoint(x: inner.minX, y: inner.minY),
            CGPoint(x: inner.maxX, y: inner.minY),
            CGPoint(x: inner.minX, y: inner.maxY),
            CGPoint(x: inner.maxX, y: inner.maxY),
        ]
        return corners.contains { cornerCenter in
            let dx = point.x - cornerCenter.x
            let dy = point.y - cornerCenter.y
            return (dx * dx) + (dy * dy) <= (corner * corner)
        }
    }
}

struct DotsView: View {
    @ObservedObject private var pointer: LauncherPointerState
    @StateObject private var tasks = TaskStore()
    @StateObject private var clipboard = ClipboardStore()
    @State private var expansion: DotExpansion = .none
    @State private var cameraOffset: CGSize = .zero

    let onExpansionChange: (DotExpansion, CGSize, Int) -> Void

    private var dotIDs: [DotID] {
        DotRegistry.visibleIDs(from: DotRegistry.defaultActiveIDs)
    }

    init(
        pointer: LauncherPointerState,
        onExpansionChange: @escaping (DotExpansion, CGSize, Int) -> Void
    ) {
        _pointer = ObservedObject(wrappedValue: pointer)
        self.onExpansionChange = onExpansionChange
    }

    var body: some View {
        let canvas = DotsLayout.canvasSize(cameraOffset: cameraOffset, dotIDs: dotIDs)

        ZStack(alignment: .topLeading) {
            if expansion == .tasks,
               let hang = DotsLayout.hangingFrame(
                   expansion: .tasks,
                   taskCount: tasks.items.count,
                   dotIDs: dotIDs
               )
            {
                expandedTasks
                    .frame(width: hang.width, height: hang.height)
                    .offset(x: hang.minX, y: hang.minY)
            }

            if expansion == .clipboard,
               let hang = DotsLayout.hangingFrame(
                   expansion: .clipboard,
                   dotIDs: dotIDs
               )
            {
                expandedClipboard
                    .frame(width: hang.width, height: hang.height)
                    .offset(x: hang.minX, y: hang.minY)
            }
        }
        .frame(
            width: canvas.width,
            height: canvas.height,
            alignment: .topLeading
        )
        .onAppear {
            notifyExpansionChange(.none, cameraOffset: .zero)
        }
        .onChange(of: expansion) { _, newExpansion in
            notifyExpansionChange(newExpansion, cameraOffset: cameraOffset)
        }
        .onChange(of: cameraOffset) { _, newOffset in
            notifyExpansionChange(expansion, cameraOffset: newOffset)
        }
        .onChange(of: tasks.items.count) { _, _ in
            notifyExpansionChange(expansion, cameraOffset: cameraOffset)
        }
        .onChange(of: pointer.activationSequence) { _, _ in
            guard let id = pointer.requestedActivation else { return }
            activate(id)
        }
        .onChange(of: pointer.dismissalSequence) { _, _ in
            guard expansion != .none else { return }
            setExpansion(.none)
        }
        .onChange(of: pointer.cameraOffset) { _, newOffset in
            cameraOffset = newOffset
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: expansion)
    }

    private var expandedTasks: some View {
        TaskListView(store: tasks)
            .contentShape(
                RoundedRectangle(
                    cornerRadius: DotsLayout.taskCornerRadius,
                    style: .continuous
                )
            )
            .environment(\.colorScheme, .dark)
    }

    private var expandedClipboard: some View {
        FeatureSurface(
            shape: RoundedRectangle(
                cornerRadius: DotsLayout.clipboardCornerRadius,
                style: .continuous
            ),
            backingOpacity: 0.72
        ) {
            ClipboardListView(store: clipboard)
        }
        .contentShape(
            RoundedRectangle(
                cornerRadius: DotsLayout.clipboardCornerRadius,
                style: .continuous
            )
        )
        .environment(\.colorScheme, .dark)
    }

    private func toggleCamera() {
        setExpansion(expansion == .camera ? .none : .camera)
    }

    private func toggleTasks() {
        setExpansion(expansion == .tasks ? .none : .tasks)
    }

    private func toggleClipboard() {
        setExpansion(expansion == .clipboard ? .none : .clipboard)
    }

    private func activate(_ id: DotID) {
        switch id {
        case .mirror:
            toggleCamera()
        case .tasks:
            toggleTasks()
        case .clipboard:
            toggleClipboard()
        case .redPen:
            setExpansion(expansion == .redPen ? .none : .redPen)
        case .screenToText:
            setExpansion(expansion == .screenToText ? .none : .screenToText)
        }
    }

    private func setExpansion(_ newExpansion: DotExpansion) {
        let isClosingCamera = expansion == .camera && newExpansion != .camera

        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            expansion = newExpansion
        }
        if !isClosingCamera {
            cameraOffset = .zero
            pointer.setCameraOffset(.zero)
        }
    }

    private func notifyExpansionChange(
        _ expansion: DotExpansion,
        cameraOffset: CGSize
    ) {
        onExpansionChange(expansion, cameraOffset, tasks.items.count)
    }
}

struct CameraPanelView: View {
    @ObservedObject var camera: CameraSession
    @ObservedObject var model: CameraPanelModel
    let onDismiss: () -> Void
    let onToggleStyle: () -> Void
    let onToggleSize: () -> Void

    @State private var isHovering = false

    init(
        camera: CameraSession,
        model: CameraPanelModel,
        onDismiss: @escaping () -> Void = {},
        onToggleStyle: @escaping () -> Void = {},
        onToggleSize: @escaping () -> Void = {}
    ) {
        self.camera = camera
        self.model = model
        self.onDismiss = onDismiss
        self.onToggleStyle = onToggleStyle
        self.onToggleSize = onToggleSize
    }

    var body: some View {
        GeometryReader { proxy in
            let surfaceSize = cameraSurfaceSize(for: proxy.size)

            ZStack(alignment: .topTrailing) {
                cameraSurface(size: surfaceSize)
                    .frame(
                        width: proxy.size.width,
                        height: proxy.size.height,
                        alignment: .topLeading
                    )

                cameraControls
            }
        }
        .frame(
            minWidth: model.style.minimumPanelSize(for: model.sizeMode).width,
            maxWidth: .infinity,
            minHeight: model.style.minimumPanelSize(for: model.sizeMode).height,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .accessibilityLabel("Selfie camera")
        .accessibilityValue(camera.accessibilityDescription)
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    private func cameraSurfaceSize(for panelSize: CGSize) -> CGSize {
        let minimum = model.style.minimumSurfaceSize(for: model.sizeMode)
        let availableWidth = max(minimum.width, panelSize.width)
        let availableHeight = max(minimum.height, panelSize.height)
        let width = min(availableWidth, availableHeight * model.style.surfaceAspectRatio)

        return CGSize(width: width, height: width / model.style.surfaceAspectRatio)
    }

    private func cameraSurface(size: CGSize) -> some View {
        let shape = MorphingCameraShape(
            progress: model.style == .circle ? 1 : 0
        )

        return FeatureSurface(shape: shape, backingOpacity: 1) {
            cameraContents(size: size)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(shape)
        .animation(
            .easeInOut(duration: CameraPanelStyle.transitionDuration),
            value: model.style
        )
    }

    private func cameraContents(size: CGSize) -> some View {
        ZStack {
            CameraPreview(session: camera.session)
                .frame(
                    width: size.width,
                    height: size.height
                )
                .opacity(camera.status == .running ? 1 : 0)
                .allowsHitTesting(false)

            cameraStatusOverlay
                .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
    }

    private var cameraControls: some View {
        let controlsAreVisible = isHovering || model.isTransitioning

        return VStack(spacing: DotsLayout.cameraControlGap) {
            CameraControlButton(
                systemName: model.style.nextSymbolName,
                accessibilityLabel: model.style.toggleAccessibilityLabel,
                action: onToggleStyle
            )
            .id("camera-style-control")
            CameraControlButton(
                systemName: model.sizeMode.nextSymbolName,
                accessibilityLabel: model.sizeMode.toggleAccessibilityLabel,
                action: onToggleSize
            )
            .id("camera-size-control")
            CameraControlButton(
                systemName: "xmark",
                accessibilityLabel: "Close camera",
                action: onDismiss
            )
            .id("camera-close-control")
        }
        .frame(
            width: DotsLayout.cameraControlSize,
            height: DotsLayout.cameraControlStackHeight
                - DotsLayout.cameraControlEdgePadding,
            alignment: .top
        )
        .padding(.top, DotsLayout.cameraControlEdgePadding)
        .padding(.trailing, DotsLayout.cameraControlEdgePadding)
        .opacity(controlsAreVisible ? 1 : 0)
        .allowsHitTesting(controlsAreVisible)
        .animation(.easeOut(duration: 0.08), value: controlsAreVisible)
    }

    @ViewBuilder
    private var cameraStatusOverlay: some View {
        switch camera.status.overlay {
        case .none:
            EmptyView()
        case .spinner:
            ProgressView()
                .controlSize(.small)
                .tint(.white)
        case .unavailable:
            Image(systemName: "video.slash.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

struct MorphingCameraShape: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clampedProgress = min(max(progress, 0), 1)
        let maximumRadius = min(rect.width, rect.height) / 2
        let startingRadius = min(DotsLayout.cameraPanelCornerRadius, maximumRadius)
        let cornerRadius = startingRadius
            + ((maximumRadius - startingRadius) * clampedProgress)

        return RoundedRectangle(
            cornerRadius: cornerRadius,
            style: .continuous
        )
        .path(in: rect)
    }
}

private struct CameraControlButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        styledButton
        .onHover { isHovering = $0 }
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var styledButton: some View {
        if #available(macOS 26.0, *) {
            Button(action: action, label: buttonLabel)
                .buttonStyle(.plain)
                .glassEffect(.clear.interactive(), in: Circle())
                .contentShape(Circle())
                .overlay {
                    CameraControlEdgeLighting(isHovering: isHovering)
                }
        } else {
            Button(action: action, label: buttonLabel)
                .buttonStyle(CameraControlButtonStyle(isHovering: isHovering))
                .overlay {
                    CameraControlEdgeLighting(isHovering: isHovering)
                }
        }
    }

    private func buttonLabel() -> some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(
                width: DotsLayout.cameraControlSize,
                height: DotsLayout.cameraControlSize
            )
            .contentShape(Circle())
    }
}

private struct CameraControlEdgeLighting: View {
    let isHovering: Bool

    var body: some View {
        Circle()
            .stroke(
                AngularGradient(
                    gradient: Gradient(stops: [
                        .init(
                            color: .white.opacity(isHovering ? 0.86 : 0.7),
                            location: 0
                        ),
                        .init(color: .white.opacity(0.1), location: 0.24),
                        .init(
                            color: .white.opacity(isHovering ? 0.7 : 0.54),
                            location: 0.5
                        ),
                        .init(color: .white.opacity(0.08), location: 0.76),
                        .init(
                            color: .white.opacity(isHovering ? 0.86 : 0.7),
                            location: 1
                        ),
                    ]),
                    center: .center,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(270)
                ),
                lineWidth: 0.9
            )
            .allowsHitTesting(false)
    }
}

private struct CameraControlButtonStyle: ButtonStyle {
    let isHovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                .ultraThinMaterial,
                in: Circle()
            )
            .overlay {
                Circle()
                    .stroke(
                        .white.opacity(isHovering ? 0.38 : 0.24),
                        lineWidth: 0.75
                    )
            }
            .overlay {
                if configuration.isPressed {
                    Circle()
                        .fill(.white.opacity(0.12))
                }
            }
            .scaleEffect(configuration.isPressed ? 0.94 : (isHovering ? 1.03 : 1))
            .animation(.easeOut(duration: configuration.isPressed ? 0.05 : 0.08), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.08), value: isHovering)
    }
}

private struct FeatureSurface<SurfaceShape: Shape, Content: View>: View {
    let shape: SurfaceShape
    let backingOpacity: Double
    let content: Content

    init(
        shape: SurfaceShape,
        backingOpacity: Double = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.shape = shape
        self.backingOpacity = backingOpacity
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            ZStack {
                shape.fill(.black.opacity(backingOpacity))
                content
            }
                .glassEffect(
                    .regular.tint(.black.opacity(0.76)),
                    in: shape
                )
                .overlay {
                    shape.stroke(.white.opacity(0.14), lineWidth: 0.75)
                }
        } else {
            ZStack {
                shape
                    .fill(.ultraThinMaterial)
                    .overlay {
                        shape.fill(.black.opacity(0.82))
                    }
                    .overlay {
                        shape.stroke(.white.opacity(0.12), lineWidth: 0.75)
                    }

                content
            }
        }
    }
}

struct TaskListView: View {
    @ObservedObject var store: TaskStore
    @State private var addDraft = ""
    @State private var hoveredTaskID: UUID?

    private var panelSize: CGSize {
        DotsLayout.taskListSize(taskCount: store.items.count)
    }

    private var contentSize: CGSize {
        DotsLayout.taskListContentSize(taskCount: store.items.count)
    }

    var body: some View {
        FeatureSurface(
            shape: RoundedRectangle(
                cornerRadius: DotsLayout.taskCornerRadius,
                style: .continuous
            ),
            backingOpacity: 0.72
        ) {
            ScrollViewReader { scrollProxy in
                ScrollView(.vertical) {
                    VStack(spacing: DotsLayout.taskRowSpacing) {
                        taskAddRow

                        ForEach(store.visibleItems) { item in
                            taskRow(item)
                                .id(item.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .frame(
                    width: contentSize.width,
                    height: contentSize.height,
                    alignment: .topLeading
                )
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                .onChange(of: store.selectedTaskID) { _, selectedTaskID in
                    guard let selectedTaskID else { return }
                    withAnimation(.easeOut(duration: 0.12)) {
                        scrollProxy.scrollTo(selectedTaskID, anchor: .center)
                    }
                }
            }
            .padding(DotsLayout.taskPanelPadding)
        }
        .frame(
            width: panelSize.width,
            height: panelSize.height,
            alignment: .topLeading
        )
    }

    private var taskAddRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.white)
                .frame(
                    width: 17,
                    height: 19,
                    alignment: .leading
                )
                .padding(.leading, DotsLayout.taskContentLeadingPadding)

            TaskComposerField(
                text: $addDraft,
                placeholder: "Add a task",
                onSubmit: addTaskDraft,
                onTextChange: store.clearTaskSelection,
                onBackspaceAtStart: store.handleBackspaceOnAddDraft,
                onMoveSelection: store.moveTaskSelection,
                onEditSelected: store.editSelectedTask
            )
                .frame(height: DotsLayout.taskRowHeight)
                .frame(maxWidth: .infinity)
                .padding(.trailing, DotsLayout.taskContentTrailingPadding)
        }
        .frame(maxWidth: .infinity)
        .frame(height: DotsLayout.taskRowHeight)
        .background {
            taskRowSurface
        }
        .contentShape(Rectangle())
    }

    private func taskRow(_ item: DotTask) -> some View {
        let rowIndex = store.visibleItems.firstIndex { $0.id == item.id } ?? 0
        let rowOpacity = taskRowOpacity(at: rowIndex)

        return HStack(spacing: 8) {
            Button {
                store.toggle(item.id)
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.white)
                    .frame(
                        width: 19,
                        height: 19,
                        alignment: .leading
                    )
                    .contentShape(Rectangle().inset(by: -2.5))
                    .padding(.leading, DotsLayout.taskContentLeadingPadding)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isDone ? "Mark \(item.title) incomplete" : "Complete \(item.title)")

            if store.editingTaskID == item.id {
                taskEditorField(placeholder: "Edit task")
                    .frame(height: DotsLayout.taskRowHeight)
                    .frame(maxWidth: .infinity)
            } else {
                Button {
                    store.editTask(item.id)
                } label: {
                    Text(item.title)
                        .font(.system(size: DotsLayout.taskFontSize, weight: .regular))
                        .foregroundStyle(.white.opacity(item.isDone ? 0.6 : 1))
                        .strikethrough(item.isDone)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                        .frame(height: DotsLayout.taskRowHeight, alignment: .center)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit \(item.title)")
            }

            if hoveredTaskID == item.id {
                Button {
                    store.remove(item.id)
                } label: {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.white)
                        .frame(
                            width: 18,
                            height: 19
                        )
                        .contentShape(Rectangle().inset(by: -3))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete \(item.title)")
                .padding(.trailing, DotsLayout.taskContentTrailingPadding)
            } else {
                Color.clear
                    .frame(
                        width: 18,
                        height: 19
                    )
                    .accessibilityHidden(true)
                    .padding(.trailing, DotsLayout.taskContentTrailingPadding)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: DotsLayout.taskRowHeight)
        .background {
            taskRowSurface
        }
        .contentShape(Rectangle())
        .opacity(rowOpacity)
        .onHover { hovering in
            hoveredTaskID = hovering ? item.id : nil
        }
        .accessibilityAction(named: "Delete task") {
            store.remove(item.id)
        }
        .accessibilityAddTraits(store.selectedTaskID == item.id ? .isSelected : [])
    }

    private var taskRowSurface: some View {
        TaskRowSurface()
    }

    private func taskRowOpacity(at index: Int) -> Double {
        guard store.visibleItems.count >= 4 else { return 1 }

        switch store.visibleItems.count - index - 1 {
        case 0:
            return 0.1
        case 1:
            return 0.4
        default:
            return 1
        }
    }

    private func taskEditorField(placeholder: String) -> some View {
        TaskComposerField(
            text: $store.draft,
            placeholder: placeholder,
            onSubmit: store.addDraft,
            onTextChange: store.clearTaskSelection,
            onBackspaceAtStart: store.handleBackspaceOnEmptyDraft,
            onMoveSelection: store.moveTaskSelection,
            onEditSelected: store.editSelectedTask
        )
    }

    private func addTaskDraft() {
        guard store.add(addDraft) != nil else { return }
        addDraft = ""
    }
}

private struct TaskRowSurface: View {
    private let shape = RoundedRectangle(
        cornerRadius: DotsLayout.taskCornerRadius,
        style: .continuous
    )

    @ViewBuilder
    var body: some View {
        shape.fill(Color(red: 122 / 255, green: 122 / 255, blue: 122 / 255))
    }
}

private struct ClipboardListView: View {
    @ObservedObject var store: ClipboardStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Clipboard")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))

            if store.items.isEmpty {
                Text("Copy something to see it here")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(store.items, id: \.self) { item in
                            Button {
                                store.copy(item)
                            } label: {
                                Text(item)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.92))
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 8)
                                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Copy clipboard item")
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(
            width: DotsLayout.clipboardSize.width,
            height: DotsLayout.clipboardSize.height,
            alignment: .topLeading
        )
    }
}

private struct TaskComposerField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void
    var onTextChange: () -> Void
    var onBackspaceAtStart: () -> Bool
    var onMoveSelection: (TaskSelectionDirection) -> Bool
    var onEditSelected: () -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            onSubmit: onSubmit,
            onTextChange: onTextChange,
            onBackspaceAtStart: onBackspaceAtStart,
            onMoveSelection: onMoveSelection,
            onEditSelected: onEditSelected
        )
    }

    func makeNSView(context: Context) -> TaskComposerHost {
        let host = TaskComposerHost()
        host.field.delegate = context.coordinator
        host.field.target = context.coordinator
        host.field.action = #selector(Coordinator.submit(_:))
        host.field.onDeleteBackwardWhenEmpty = { [weak coordinator = context.coordinator] in
            coordinator?.handleBackspaceAtStart()
        }
        host.updatePlaceholder(placeholder)
        return host
    }

    func updateNSView(_ nsView: TaskComposerHost, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit
        context.coordinator.onTextChange = onTextChange
        context.coordinator.onBackspaceAtStart = onBackspaceAtStart
        context.coordinator.onMoveSelection = onMoveSelection
        context.coordinator.onEditSelected = onEditSelected
        nsView.updatePlaceholder(placeholder)
        let editor = nsView.field.currentEditor()
        let isEditing = editor != nil && nsView.window?.firstResponder === editor
        if nsView.field.stringValue != text {
            if text.isEmpty {
                nsView.field.stringValue = ""
                editor?.string = ""
            } else if !isEditing {
                nsView.field.stringValue = text
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onSubmit: () -> Void
        var onTextChange: () -> Void
        var onBackspaceAtStart: () -> Bool
        var onMoveSelection: (TaskSelectionDirection) -> Bool
        var onEditSelected: () -> Bool

        init(
            text: Binding<String>,
            onSubmit: @escaping () -> Void,
            onTextChange: @escaping () -> Void,
            onBackspaceAtStart: @escaping () -> Bool,
            onMoveSelection: @escaping (TaskSelectionDirection) -> Bool,
            onEditSelected: @escaping () -> Bool
        ) {
            self.text = text
            self.onSubmit = onSubmit
            self.onTextChange = onTextChange
            self.onBackspaceAtStart = onBackspaceAtStart
            self.onMoveSelection = onMoveSelection
            self.onEditSelected = onEditSelected
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
            onTextChange()
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard let field = control as? FocusableTextField else {
                return false
            }

            switch commandSelector {
            case #selector(NSResponder.deleteBackward(_:)):
                return field.handleDeleteBackward(in: textView)
            case #selector(NSResponder.moveUp(_:)):
                return onMoveSelection(.up)
            case #selector(NSResponder.moveDown(_:)):
                return onMoveSelection(.down)
            case #selector(NSResponder.insertNewline(_:)):
                guard onEditSelected() else { return false }
                field.replaceText(text.wrappedValue, in: textView)
                return true
            default:
                return false
            }
        }

        @objc func submit(_ sender: NSTextField) {
            text.wrappedValue = sender.stringValue
            onSubmit()
            sender.stringValue = text.wrappedValue
            sender.currentEditor()?.string = text.wrappedValue
        }

        func handleBackspaceAtStart() -> String? {
            guard onBackspaceAtStart() else { return nil }
            return text.wrappedValue
        }
    }
}

final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    override func titleRect(forBounds rect: NSRect) -> NSRect {
        centeredTextRect(forBounds: rect)
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        centeredTextRect(forBounds: rect)
    }

    override func edit(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObject: NSText,
        delegate: Any?,
        event: NSEvent?
    ) {
        super.edit(
            withFrame: editorTextRect(forBounds: rect),
            in: controlView,
            editor: textObject,
            delegate: delegate,
            event: event
        )
    }

    override func select(
        withFrame rect: NSRect,
        in controlView: NSView,
        editor textObject: NSText,
        delegate: Any?,
        start selectionStart: Int,
        length selectionLength: Int
    ) {
        super.select(
            withFrame: editorTextRect(forBounds: rect),
            in: controlView,
            editor: textObject,
            delegate: delegate,
            start: selectionStart,
            length: selectionLength
        )
    }

    func editorTextRect(forBounds rect: NSRect) -> NSRect {
        centeredTextRect(
            forBounds: rect,
            verticalOffset: DotsLayout.taskEditingTextVerticalOffset
        )
    }

    private func centeredTextRect(
        forBounds rect: NSRect,
        verticalOffset: CGFloat = 0
    ) -> NSRect {
        let baseRect = super.titleRect(forBounds: rect)
        let textHeight = ceil(
            (font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize))
                .boundingRectForFont.height
        )
        let centeredY = floor(rect.midY - (textHeight / 2) + verticalOffset)

        return NSRect(
            x: baseRect.minX,
            y: centeredY,
            width: baseRect.width,
            height: textHeight
        )
    }
}

private final class TaskComposerHost: NSView {
    let field = FocusableTextField()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        appearance = NSAppearance(named: .darkAqua)
        field.cell = VerticallyCenteredTextFieldCell(textCell: "")
        field.isEditable = true
        field.isSelectable = true
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: DotsLayout.taskFontSize, weight: .regular)
        field.alignment = .left
        field.textColor = .white
        field.appearance = NSAppearance(named: .darkAqua)
        field.setAccessibilityLabel("New task")
        field.setAccessibilityHelp(
            "Type a task and press Return to save it. Use the arrow keys to select a task and Return to edit it. Press Delete in an empty field to edit the previous task."
        )
        updatePlaceholder("Add a task")
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.cell?.usesSingleLineMode = true
        field.refusesFirstResponder = false
        addSubview(field)
    }

    func updatePlaceholder(_ placeholder: String) {
        field.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.6),
                .font: NSFont.systemFont(
                    ofSize: DotsLayout.taskFontSize,
                    weight: .regular
                ),
            ]
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        field.frame = bounds.insetBy(dx: 0, dy: 1)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: DotsLayout.taskRowHeight)
    }
}

final class FocusableTextField: NSTextField {
    var onDeleteBackwardWhenEmpty: (() -> String?)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            self?.focusForTaskEntry()
        }
    }

    override func mouseDown(with event: NSEvent) {
        focusForTaskEntry()
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51,
           handleDeleteBackward(in: currentEditor() as? NSTextView) {
            return
        }
        super.keyDown(with: event)
    }

    fileprivate func handleDeleteBackward(in editor: NSTextView?) -> Bool {
        let currentText = editor?.string ?? stringValue
        guard currentText.isEmpty,
              let replacement = onDeleteBackwardWhenEmpty?()
        else {
            return false
        }

        replaceText(replacement, in: editor)
        return true
    }

    fileprivate func replaceText(_ replacement: String, in editor: NSTextView?) {
        stringValue = replacement
        editor?.string = replacement
        editor?.setSelectedRange(
            NSRange(location: replacement.utf16.count, length: 0)
        )
    }

    override func becomeFirstResponder() -> Bool {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        let accepted = super.becomeFirstResponder()
        if accepted, let editor = currentEditor() as? NSTextView {
            editor.allowsUndo = true
            editor.insertionPointColor = .white
            editor.textColor = .white
        }
        return accepted
    }

    private func focusForTaskEntry() {
        guard let window else { return }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        guard window.makeFirstResponder(self),
              let editor = currentEditor() as? NSTextView
        else {
            return
        }
        editor.setSelectedRange(
            NSRange(location: stringValue.utf16.count, length: 0)
        )
    }
}
