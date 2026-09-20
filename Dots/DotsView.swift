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
enum DotsLayout {
    static let nodeDiameter: CGFloat = 16
    static let cameraDiameter: CGFloat = 120
    static let nodeSpacing: CGFloat = 16
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 8
    static let dotHitSlop: CGFloat = 6
    static let hangingGap: CGFloat = 8
    static let taskListWidth: CGFloat = 300
    static let taskListMinimumHeight: CGFloat = 168
    static let taskListMaximumHeight: CGFloat = 420
    static let taskListRowGrowth: CGFloat = 30
    static let taskCornerRadius: CGFloat = 16
    static let taskControlHitSize: CGFloat = 24
    static let clipboardSize = CGSize(width: 240, height: 220)
    static let glassInset: CGFloat = 12

    static func taskListSize(taskCount: Int) -> CGSize {
        let rowCount = max(0, taskCount)
        return CGSize(
            width: taskListWidth,
            height: min(
                taskListMaximumHeight,
                taskListMinimumHeight + (CGFloat(rowCount) * taskListRowGrowth)
            )
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
        for index in ids.indices {
            let dotTarget = frames[index].insetBy(dx: -dotHitSlop, dy: -dotHitSlop)
            if circleContains(dotTarget, point) {
                return ids[index]
            }
        }
        return nil
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
                y: dot.maxY + hangingGap,
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
            return CGRect(
                x: dot.midX - (size.width / 2),
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
    @StateObject private var camera = CameraSession()
    @StateObject private var tasks = TaskStore()
    @StateObject private var clipboard = ClipboardStore()
    @State private var expansion: DotExpansion = .none
    @State private var cameraOffset: CGSize = .zero
    @State private var cameraDragStart: CGSize = .zero

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
            if expansion == .camera,
               let hang = DotsLayout.hangingFrame(
                   expansion: .camera,
                   cameraOffset: cameraOffset,
                   dotIDs: dotIDs
               )
            {
                expandedCamera
                    .frame(width: hang.width, height: hang.height)
                    .offset(x: hang.minX, y: hang.minY)
            }

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
            cameraDragStart = newOffset
        }
        .onDisappear {
            camera.stop()
        }
    }

    private var expandedCamera: some View {
        FeatureSurface(shape: Circle()) {
            ZStack {
                CameraPreview(session: camera.session)
                    .opacity(camera.status == .running ? 1 : 0)

                cameraStatusOverlay

                Circle()
                    .stroke(.white.opacity(0.16), lineWidth: 0.75)
            }
            .clipShape(Circle())
        }
        .contentShape(Circle())
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Close selfie camera")
        .accessibilityValue(camera.accessibilityDescription)
        .accessibilityHint("Drag to place the camera. Click to close.")
    }

    private var expandedTasks: some View {
        FeatureSurface(
            shape: RoundedRectangle(
                cornerRadius: DotsLayout.taskCornerRadius,
                style: .continuous
            ),
            backingOpacity: 0.72
        ) {
            TaskListView(store: tasks)
        }
        .contentShape(
            RoundedRectangle(cornerRadius: DotsLayout.taskCornerRadius, style: .continuous)
        )
        .environment(\.colorScheme, .dark)
    }

    private var expandedClipboard: some View {
        FeatureSurface(
            shape: RoundedRectangle(
                cornerRadius: DotsLayout.taskCornerRadius,
                style: .continuous
            ),
            backingOpacity: 0.72
        ) {
            ClipboardListView(store: clipboard)
        }
        .contentShape(
            RoundedRectangle(cornerRadius: DotsLayout.taskCornerRadius, style: .continuous)
        )
        .environment(\.colorScheme, .dark)
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
        if newExpansion == .camera {
            camera.start()
            expansion = newExpansion
            return
        }

        camera.stop()
        expansion = newExpansion
        cameraOffset = .zero
        cameraDragStart = .zero
        pointer.setCameraOffset(.zero)
    }

    private func notifyExpansionChange(
        _ expansion: DotExpansion,
        cameraOffset: CGSize
    ) {
        onExpansionChange(expansion, cameraOffset, tasks.items.count)
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
    @State private var hoveredTaskID: UUID?

    private var panelSize: CGSize {
        DotsLayout.taskListSize(taskCount: store.items.count)
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    Text("Tasks")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))

                    if store.items.isEmpty {
                        Text("No tasks")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.62))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(store.visibleItems) { item in
                            taskRow(item)
                                .id(item.id)
                        }
                    }

                    TaskComposerField(
                        text: $store.draft,
                        placeholder: store.editingTaskID == nil ? "Add a task" : "Edit task",
                        onSubmit: store.addDraft,
                        onTextChange: store.clearTaskSelection,
                        onBackspaceAtStart: store.handleBackspaceOnEmptyDraft,
                        onMoveSelection: store.moveTaskSelection,
                        onEditSelected: store.editSelectedTask
                    )
                    .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onChange(of: store.selectedTaskID) { _, selectedTaskID in
                guard let selectedTaskID else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    scrollProxy.scrollTo(selectedTaskID, anchor: .center)
                }
            }
        }
        .frame(
            width: panelSize.width,
            height: panelSize.height,
            alignment: .topLeading
        )
        .contentShape(
            RoundedRectangle(cornerRadius: DotsLayout.taskCornerRadius, style: .continuous)
        )
    }

    private func taskRow(_ item: DotTask) -> some View {
        HStack(spacing: 8) {
            Button {
                store.toggle(item.id)
            } label: {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(item.isDone ? 0.55 : 0.9), lineWidth: 1.5)
                    if item.isDone {
                        Circle()
                            .fill(.white.opacity(0.9))
                            .padding(3)
                    }
                }
                .frame(width: 14, height: 14)
                .frame(
                    width: DotsLayout.taskControlHitSize,
                    height: DotsLayout.taskControlHitSize
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isDone ? "Mark \(item.title) incomplete" : "Complete \(item.title)")

            Text(item.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(item.isDone ? 0.62 : 0.95))
                .strikethrough(item.isDone)
                .lineLimit(2)

            Spacer(minLength: 4)

            if hoveredTaskID == item.id {
                Button {
                    store.remove(item.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(
                            width: DotsLayout.taskControlHitSize,
                            height: DotsLayout.taskControlHitSize
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Delete \(item.title)")
            } else {
                Color.clear
                    .frame(
                        width: DotsLayout.taskControlHitSize,
                        height: DotsLayout.taskControlHitSize
                    )
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 24)
        .padding(.horizontal, 4)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(
                    .white.opacity(store.selectedTaskID == item.id ? 0.12 : 0)
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(
                    .white.opacity(store.selectedTaskID == item.id ? 0.16 : 0),
                    lineWidth: 0.75
                )
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredTaskID = hovering ? item.id : nil
        }
        .accessibilityAction(named: "Delete task") {
            store.remove(item.id)
        }
        .accessibilityAddTraits(store.selectedTaskID == item.id ? .isSelected : [])
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

private final class TaskComposerHost: NSView {
    let field = FocusableTextField()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        appearance = NSAppearance(named: .darkAqua)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13, weight: .medium)
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
                .foregroundColor: NSColor.white.withAlphaComponent(0.58),
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            ]
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        field.frame = bounds
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 24)
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
        window.makeFirstResponder(self)
    }
}
