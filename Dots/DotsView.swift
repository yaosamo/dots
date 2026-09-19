import AppKit
import SwiftUI

enum DotExpansion: Equatable {
    case none
    case camera
    case tasks
}

enum DotsLayout {
    static let nodeDiameter: CGFloat = 16
    static let cameraDiameter: CGFloat = 120
    static let nodeSpacing: CGFloat = 16
    static let horizontalPadding: CGFloat = 12
    static let verticalPadding: CGFloat = 8
    static let stemThickness: CGFloat = 2
    static let stemHitSlop: CGFloat = 4
    static let hangingGap: CGFloat = 8
    static let taskListSize = CGSize(width: 200, height: 240)
    static let taskCornerRadius: CGFloat = 16

    static var rowContentSize: CGSize {
        CGSize(
            width: (nodeDiameter * 4) + (nodeSpacing * 3),
            height: nodeDiameter
        )
    }

    static var rowPanelSize: CGSize {
        CGSize(
            width: rowContentSize.width + (horizontalPadding * 2),
            height: rowContentSize.height + (verticalPadding * 2)
        )
    }

    static func extraLeft(expansion: DotExpansion) -> CGFloat {
        max(0, -(hangingRectInRowCoordinates(expansion: expansion)?.minX ?? 0))
    }

    static func panelSize(expansion: DotExpansion) -> CGSize {
        let row = rowPanelSize
        guard let hang = hangingRectInRowCoordinates(expansion: expansion) else {
            return row
        }

        let minX = min(0, hang.minX)
        let maxX = max(row.width, hang.maxX)
        let maxY = max(row.height, hang.maxY + verticalPadding)
        return CGSize(width: maxX - minX, height: maxY)
    }

    static func nodeFrames(expansion: DotExpansion) -> [CGRect] {
        let dx = extraLeft(expansion: expansion)
        return collapsedNodeFrames().map { $0.offsetBy(dx: dx, dy: 0) }
    }

    static func hangingFrame(expansion: DotExpansion) -> CGRect? {
        hangingRectInRowCoordinates(expansion: expansion)?
            .offsetBy(dx: extraLeft(expansion: expansion), dy: 0)
    }

    static func stemRects(expansion: DotExpansion) -> [CGRect] {
        nodeFrames(expansion: expansion).map { frame in
            CGRect(
                x: frame.midX - (stemThickness / 2),
                y: 0,
                width: stemThickness,
                height: frame.midY
            )
        }
    }

    static func containsInteractiveContent(
        _ point: CGPoint,
        expansion: DotExpansion
    ) -> Bool {
        if nodeFrames(expansion: expansion).contains(where: { circleContains($0, point) }) {
            return true
        }

        if let hang = hangingFrame(expansion: expansion) {
            switch expansion {
            case .camera:
                if circleContains(hang, point) { return true }
            case .tasks:
                if roundedRectContains(hang, radius: taskCornerRadius, point: point) {
                    return true
                }
            case .none:
                break
            }
        }

        return stemRects(expansion: expansion).contains { stem in
            stem.insetBy(dx: -stemHitSlop, dy: 0).contains(point)
        }
    }

    static func panelFrame(
        size: CGSize,
        expansion: DotExpansion,
        previousExpansion: DotExpansion = .none,
        keepingTopOf existingFrame: CGRect? = nil,
        visibleFrame: CGRect
    ) -> CGRect {
        let rowCenter = extraLeft(expansion: expansion) + (rowPanelSize.width / 2)

        if let existingFrame {
            let previousRowCenter = extraLeft(expansion: previousExpansion) + (rowPanelSize.width / 2)
            let screenRowCenter = existingFrame.minX + previousRowCenter
            return CGRect(
                x: screenRowCenter - rowCenter,
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

    private static func collapsedNodeFrames() -> [CGRect] {
        var x = horizontalPadding
        return (0..<4).map { _ in
            let frame = CGRect(
                x: x,
                y: verticalPadding,
                width: nodeDiameter,
                height: nodeDiameter
            )
            x += nodeDiameter + nodeSpacing
            return frame
        }
    }

    private static func hangingRectInRowCoordinates(expansion: DotExpansion) -> CGRect? {
        let nodes = collapsedNodeFrames()
        switch expansion {
        case .none:
            return nil
        case .camera:
            let dot = nodes[0]
            return CGRect(
                x: dot.midX - (cameraDiameter / 2),
                y: dot.maxY + hangingGap,
                width: cameraDiameter,
                height: cameraDiameter
            )
        case .tasks:
            let dot = nodes[1]
            return CGRect(
                x: dot.midX - (taskListSize.width / 2),
                y: dot.maxY + hangingGap,
                width: taskListSize.width,
                height: taskListSize.height
            )
        }
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

enum DotsMotion {
    static let hoverInDuration = 0.08
    static let hoverOutDuration = 0.12
    static let pressInDuration = 0.05
    static let pressOutDuration = 0.09
    static let selectionDuration = 0.16

    static var selectionAnimation: Animation {
        .easeOut(duration: selectionDuration)
    }

    static var panelTimingFunction: CAMediaTimingFunction {
        CAMediaTimingFunction(name: .easeOut)
    }
}

struct DotsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var camera = CameraSession()
    @StateObject private var tasks = TaskStore()
    @State private var expansion: DotExpansion = .none
    @State private var hoveredDot: Int?

    let onWindowSizeChange: (CGSize, Bool, DotExpansion) -> Void

    var body: some View {
        let panelSize = DotsLayout.panelSize(expansion: expansion)
        let stems = DotsLayout.stemRects(expansion: expansion)
        let extraLeft = DotsLayout.extraLeft(expansion: expansion)

        ZStack(alignment: .topLeading) {
            ForEach(stems.indices, id: \.self) { index in
                let stem = stems[index]

                Rectangle()
                    .fill(.black)
                    .frame(width: stem.width, height: stem.height)
                    .offset(x: stem.minX, y: stem.minY)
            }

            HStack(alignment: .top, spacing: DotsLayout.nodeSpacing) {
                cameraButton
                taskButton
                decorativeDot
                decorativeDot
            }
            .padding(.leading, extraLeft + DotsLayout.horizontalPadding)
            .padding(.top, DotsLayout.verticalPadding)

            if expansion == .camera, let hang = DotsLayout.hangingFrame(expansion: .camera) {
                hangingCamera
                    .frame(width: hang.width, height: hang.height)
                    .offset(x: hang.minX, y: hang.minY)
            }

            if expansion == .tasks, let hang = DotsLayout.hangingFrame(expansion: .tasks) {
                TaskListView(store: tasks)
                    .offset(x: hang.minX, y: hang.minY)
            }
        }
        .frame(width: panelSize.width, height: panelSize.height, alignment: .topLeading)
        .onAppear {
            onWindowSizeChange(DotsLayout.panelSize(expansion: .none), false, .none)
        }
        .onChange(of: expansion) { _, newExpansion in
            onWindowSizeChange(
                DotsLayout.panelSize(expansion: newExpansion),
                !reduceMotion,
                newExpansion
            )
        }
        .onDisappear {
            camera.stop()
        }
    }

    private var cameraButton: some View {
        Button(action: toggleCamera) {
            Circle()
                .fill(.black)
                .frame(
                    width: DotsLayout.nodeDiameter,
                    height: DotsLayout.nodeDiameter
                )
                .contentShape(Circle())
        }
        .buttonStyle(DotPressStyle(reduceMotion: reduceMotion))
        .scaleEffect(hoveredDot == 0 ? 1.04 : 1)
        .animation(hoverAnimation(for: 0), value: hoveredDot == 0)
        .onHover { hovering in
            hoveredDot = hovering ? 0 : nil
        }
        .accessibilityLabel(expansion == .camera ? "Close selfie camera" : "Open selfie camera")
        .accessibilityValue(camera.accessibilityDescription)
    }

    private var hangingCamera: some View {
        ZStack {
            Circle()
                .fill(.black)

            CameraPreview(session: camera.session)
                .opacity(camera.status == .running ? 1 : 0)

            cameraStatusOverlay
        }
        .clipShape(Circle())
        .overlay {
            Circle()
                .stroke(.black, lineWidth: DotsLayout.stemThickness)
        }
        .allowsHitTesting(false)
    }

    private var taskButton: some View {
        Button(action: toggleTasks) {
            Circle()
                .fill(.black)
                .frame(
                    width: DotsLayout.nodeDiameter,
                    height: DotsLayout.nodeDiameter
                )
                .contentShape(Circle())
        }
        .buttonStyle(DotPressStyle(reduceMotion: reduceMotion))
        .scaleEffect(hoveredDot == 1 ? 1.04 : 1)
        .animation(hoverAnimation(for: 1), value: hoveredDot == 1)
        .onHover { hovering in
            hoveredDot = hovering ? 1 : nil
        }
        .accessibilityLabel(expansion == .tasks ? "Close task list" : "Open task list")
        .accessibilityValue("\(tasks.items.filter { !$0.isDone }.count) open")
    }

    private var decorativeDot: some View {
        Button(action: {}) {
            Circle()
                .fill(.black)
                .frame(
                    width: DotsLayout.nodeDiameter,
                    height: DotsLayout.nodeDiameter
                )
                .contentShape(Circle())
        }
        .buttonStyle(DotPressStyle(reduceMotion: reduceMotion))
        .accessibilityHidden(true)
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

    private func hoverAnimation(for index: Int) -> Animation? {
        reduceMotion
            ? nil
            : .easeOut(
                duration: hoveredDot == index
                    ? DotsMotion.hoverInDuration
                    : DotsMotion.hoverOutDuration
            )
    }

    private func toggleCamera() {
        setExpansion(expansion == .camera ? .none : .camera)
    }

    private func toggleTasks() {
        setExpansion(expansion == .tasks ? .none : .tasks)
    }

    private func setExpansion(_ newExpansion: DotExpansion) {
        if newExpansion == .camera {
            camera.start()
        } else {
            camera.stop()
        }

        if reduceMotion {
            expansion = newExpansion
        } else {
            withAnimation(DotsMotion.selectionAnimation) {
                expansion = newExpansion
            }
        }
    }
}

struct TaskListView: View {
    @ObservedObject var store: TaskStore
    @State private var hoveredTaskID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if store.items.isEmpty {
                        Text("No tasks")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.45))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(store.items) { item in
                            taskRow(item)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TaskComposerField(text: $store.draft, onSubmit: store.addDraft)
                    .frame(maxWidth: .infinity, minHeight: 18, maxHeight: 18)

                Button(action: store.addDraft) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add task")
            }
        }
        .padding(12)
        .frame(
            width: DotsLayout.taskListSize.width,
            height: DotsLayout.taskListSize.height,
            alignment: .topLeading
        )
        .background(
            Color.black,
            in: RoundedRectangle(cornerRadius: DotsLayout.taskCornerRadius, style: .continuous)
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
                        .stroke(.white.opacity(item.isDone ? 0.35 : 0.9), lineWidth: 1.5)
                    if item.isDone {
                        Circle()
                            .fill(.white.opacity(0.9))
                            .padding(3)
                    }
                }
                .frame(width: 12, height: 12)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.isDone ? "Mark \(item.title) incomplete" : "Complete \(item.title)")

            Text(item.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(item.isDone ? 0.4 : 0.95))
                .strikethrough(item.isDone)
                .lineLimit(2)

            Spacer(minLength: 4)

            Button {
                store.remove(item.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(hoveredTaskID == item.id ? 0.7 : 0.28))
                    .frame(width: 12, height: 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete \(item.title)")
        }
        .onHover { hovering in
            hoveredTaskID = hovering ? item.id : nil
        }
    }
}

private struct TaskComposerField: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> TaskComposerHost {
        let host = TaskComposerHost()
        host.field.delegate = context.coordinator
        host.field.target = context.coordinator
        host.field.action = #selector(Coordinator.submit(_:))
        DispatchQueue.main.async {
            host.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            host.window?.makeFirstResponder(host.field)
        }
        return host
    }

    func updateNSView(_ nsView: TaskComposerHost, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onSubmit = onSubmit
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

        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            self.text = text
            self.onSubmit = onSubmit
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            text.wrappedValue = field.stringValue
        }

        @objc func submit(_ sender: NSTextField) {
            text.wrappedValue = sender.stringValue
            onSubmit()
            sender.stringValue = text.wrappedValue
            sender.currentEditor()?.string = text.wrappedValue
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
        field.font = .systemFont(ofSize: 11, weight: .medium)
        field.textColor = .white
        field.appearance = NSAppearance(named: .darkAqua)
        field.placeholderAttributedString = NSAttributedString(
            string: "Add a task",
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.4),
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            ]
        )
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.cell?.usesSingleLineMode = true
        field.refusesFirstResponder = false
        addSubview(field)
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
        NSSize(width: NSView.noIntrinsicMetric, height: 18)
    }
}

private final class FocusableTextField: NSTextField {
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        let accepted = super.becomeFirstResponder()
        if accepted, let editor = currentEditor() as? NSTextView {
            editor.insertionPointColor = .white
            editor.textColor = .white
        }
        return accepted
    }
}

private struct DotPressStyle: ButtonStyle {
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(
                reduceMotion
                    ? nil
                    : .easeOut(
                        duration: configuration.isPressed
                            ? DotsMotion.pressInDuration
                            : DotsMotion.pressOutDuration
                    ),
                value: configuration.isPressed
            )
    }
}
