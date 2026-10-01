import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class TaskOverlayController: DotFeature {
    private let store = TaskStore()
    private let panel = FloatingPanel(level: DotsLevel.tasks, keyable: true)
    private let onVisibilityChange: (Bool) -> Void
    private var keyMonitor: Any?
    private var state: TaskListState?

    /// Off as soon as it starts closing, so the shortcut can reopen it during the exit.
    var isVisible: Bool { state.map { !$0.isDismissing } ?? false }

    init(onVisibilityChange: @escaping (Bool) -> Void) {
        self.onVisibilityChange = onVisibilityChange
        panel.onCancel = { [weak self] in self?.hide() }
    }

    func show() {
        guard !isVisible, let screen = NSScreen.underMouse else { return }
        panel.setFrame(screen.frame, display: false)
        panel.appearance = DotsAppearance.panelAppearance
        // Fresh view and selection each time: focus starts in "Add a task…" and the reveal replays.
        let state = TaskListState(store: store)
        self.state = state
        panel.contentView = FirstClickHostingView(
            rootView: TaskOverlayView(store: store, state: state)
        )
        // Arrow keys, Return and Esc are read here so they work even while a text field has focus.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let isConsumed = MainActor.assumeIsolated { () -> Bool in
                guard let self, event.window === self.panel else { return false }
                switch state.handle(event) {
                case .handled: return true
                case .ignored: return false
                case .close:
                    self.hide()
                    return true
                }
            }
            return isConsumed ? nil : event
        }
        panel.makeKeyAndOrderFront(nil)
        onVisibilityChange(true)
    }

    /// Plays the reveal backwards, then removes the panel. Every way of closing ends up here.
    func hide() {
        guard isVisible, let state, !state.isDismissing else { return }
        state.commitEdit()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        state.isDismissing = true
        onVisibilityChange(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + TaskOverlayView.exitDuration) { [weak self] in
            // Reopened meanwhile: that's a new state, and it stays.
            guard let self, self.state === state else { return }
            self.panel.orderOut(nil)
            self.panel.contentView = nil
            self.state = nil
        }
    }
}

/// Keyboard selection and inline editing. ↑/↓ move between "Add a task…" and the tasks,
/// Return (or a click) edits the selected task. Return saves and opens a new, empty task right
/// after it, which goes away again if it's left empty. Backspace in an empty task deletes it
/// (not a task with subtasks) and goes on editing the one above. Esc cancels the edit, then
/// deselects, then closes.
/// Tab makes the selected task a subtask of the one above, ⇧Tab makes it a task again, and
/// ←/→ fold and unfold a task's subtasks.
@MainActor
final class TaskListState: ObservableObject {
    enum Focus: Equatable {
        case input
        case task(TaskItem.ID)
        case editing(TaskItem.ID)
    }

    enum KeyResult { case handled, ignored, close }

    @Published var focus: Focus = .input
    @Published var editText = ""
    /// What's typed in "Add a task…".
    @Published var draft = ""
    /// The title when editing began: until it changes, ⌘Z restores a deleted task rather than
    /// undoing typing.
    private var editOriginal = ""
    /// Set by the controller when closing starts; the view then plays its exit.
    @Published var isDismissing = false

    private let store: TaskStore

    init(store: TaskStore) {
        self.store = store
    }

    var selectedID: TaskItem.ID? {
        switch focus {
        case .input: nil
        case .task(let id), .editing(let id): id
        }
    }

    func handle(_ event: NSEvent) -> KeyResult {
        switch Int(event.keyCode) {
        case kVK_UpArrow:
            return move(by: -1)
        case kVK_DownArrow:
            return move(by: 1)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            switch focus {
            case .input: return .ignored // the field's onSubmit adds the task
            case .task(let id): beginEditing(id)
            case .editing(let id): if commitEdit() { addTask(after: id) }
            }
            return .handled
        case kVK_Delete:
            guard case .editing(let id) = focus, editText.isEmpty, !store.hasSubtasks(id) else { return .ignored }
            let previous = rowAbove(id)
            focus = .input
            withAnimation(.spring(response: 0.3)) { store.delete(id) }
            if let previous { beginEditing(previous) }
            return .handled
        case kVK_ANSI_Z where event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command:
            return restoreDeleted() ? .handled : .ignored
        case kVK_Tab:
            guard let id = selectedID else { return .ignored }
            // A new task keeps being typed into as it moves in or out; any other edit is saved.
            if !isNew(id) { commitEdit() }
            withAnimation(.spring(response: 0.3)) {
                if event.modifierFlags.contains(.shift) { store.outdent(id) } else { store.indent(id) }
            }
            return .handled
        case kVK_LeftArrow, kVK_RightArrow:
            guard case .task(let id) = focus, store.hasSubtasks(id) else { return .ignored }
            withAnimation(.spring(response: 0.3)) { store.setCollapsed(id, Int(event.keyCode) == kVK_LeftArrow) }
            return .handled
        case kVK_Escape:
            // Steps back one level at a time: the edit, then the selection, then the overlay.
            switch focus {
            case .editing: cancelEdit()
            case .task: focus = .input
            case .input: return .close
            }
            return .handled
        default:
            return .ignored
        }
    }

    func beginEditing(_ id: TaskItem.ID) {
        commitEdit()
        guard let task = store.tasks.first(where: { $0.id == id }) else { return }
        editText = task.title
        editOriginal = task.title
        focus = .editing(id)
    }

    /// Saves the edit. A new task left empty goes away instead, and the row above it is selected;
    /// returns false then.
    @discardableResult
    func commitEdit() -> Bool {
        guard case .editing(let id) = focus else { return false }
        if isNew(id), editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            discard(id)
            return false
        }
        store.rename(id, to: editText)
        focus = .task(id)
        return true
    }

    func focusInput() {
        commitEdit()
        focus = .input
    }

    private func cancelEdit() {
        guard case .editing(let id) = focus else { return }
        if isNew(id) { discard(id) } else { focus = .task(id) }
    }

    /// Only a task that's just been added with Return has no title.
    private func isNew(_ id: TaskItem.ID) -> Bool {
        store.task(id)?.title.isEmpty == true
    }

    private func addTask(after id: TaskItem.ID) {
        guard let new = withAnimation(.spring(response: 0.3), { store.insertEmpty(after: id) }) else { return }
        editText = ""
        editOriginal = ""
        focus = .editing(new)
    }

    /// While text is being typed, ⌘Z undoes the typing; otherwise it brings back the last deleted
    /// task and selects it.
    private func restoreDeleted() -> Bool {
        switch focus {
        case .input: guard draft.isEmpty else { return false }
        case .editing: guard editText == editOriginal else { return false }
        case .task: break
        }
        guard store.canRestore else { return false }
        commitEdit()
        guard let id = withAnimation(.spring(response: 0.3), { store.restoreDeleted() }) else { return false }
        focus = .task(id)
        return true
    }

    /// A new task left empty: removed for good, nothing to undo.
    private func discard(_ id: TaskItem.ID) {
        let previous = rowAbove(id)
        withAnimation(.spring(response: 0.3)) { store.delete(id, undoable: false) }
        focus = previous.map(Focus.task) ?? .input
    }

    private func rowAbove(_ id: TaskItem.ID) -> TaskItem.ID? {
        let ids = store.visibleTasks().map(\.id)
        guard let index = ids.firstIndex(of: id), index > 0 else { return nil }
        return ids[index - 1]
    }

    private func move(by step: Int) -> KeyResult {
        let ids = store.visibleTasks().map(\.id)
        switch focus {
        case .editing:
            return .ignored
        case .input:
            // ↑ in the field keeps its normal caret behavior.
            guard step > 0, let first = ids.first else { return .ignored }
            focus = .task(first)
        case .task(let id):
            guard let index = ids.firstIndex(of: id) else {
                focus = .input
                return .handled
            }
            let next = index + step
            if next < 0 {
                focus = .input
            } else if next < ids.count {
                focus = .task(ids[next])
            }
        }
        return .handled
    }
}

struct TaskOverlayView: View {
    fileprivate enum Field: Hashable { case input, editor }

    private enum Metrics {
        static let columnWidth: CGFloat = 780
        /// Room beside the rows so shadows aren't clipped by the scroll view and its fade mask.
        /// Sized for the dragged row: 16pt blur plus its 1.02 scale (~8pt a side), plus how far it
        /// can be pulled sideways (`dragSlack`), with margin.
        static let shadowRoom: CGFloat = 80
        /// How far past either level the dragged row follows the pointer sideways.
        static let dragSlack: CGFloat = 12
        static let topFade: CGFloat = 28
        static let bottomFade: CGFloat = 240
        /// How far subtasks sit in. Dragging a row more than half of this to the right
        /// (or a subtask that far left) changes its level.
        static let indent: CGFloat = 44
        static let rowSpacing: CGFloat = 12
    }

    // Entering: frost, field and the task cascade all start together.
    // Exiting plays it backwards: tasks leave bottom-up, then the field, then the frost
    // clears from the edges into the middle.
    /// Frost timings (ShaderTuning). Everything else is timed around them.
    private static var frostInDuration: TimeInterval { ShaderTuning.values.frostInDuration }
    private static var frostOutDuration: TimeInterval { ShaderTuning.values.frostOutDuration }
    /// When closing, the frost starts clearing once the tasks and field are on their way out.
    private static let frostOutDelay: TimeInterval = 0.12

    private static var frostIn: Animation { .easeOut(duration: frostInDuration) }
    private static var frostOut: Animation { .easeIn(duration: frostOutDuration).delay(frostOutDelay) }
    private static let contentIn = Animation.easeOut(duration: 0.25)
    private static let contentOut = Animation.easeIn(duration: 0.16).delay(0.08)
    private static func cascadeIn(_ index: Int) -> Animation {
        .spring(response: 0.4, dampingFraction: 0.85).delay(0.05 + Double(min(index, 14)) * 0.04)
    }
    private static func cascadeOut(_ index: Int, of count: Int) -> Animation {
        .easeIn(duration: 0.14).delay(Double(max(0, min(count, 15) - 1 - min(index, 14))) * 0.012)
    }
    /// How long the controller waits before removing the panel: until the frost has cleared.
    static var exitDuration: TimeInterval { frostOutDelay + frostOutDuration + 0.05 }

    private var contentAnimation: Animation { isRevealed ? Self.contentIn : Self.contentOut }
    private var palette: TaskPalette { TaskPalette(scheme: colorScheme) }

    @ObservedObject var store: TaskStore
    @ObservedObject var state: TaskListState

    @Environment(\.colorScheme) private var colorScheme

    /// The task being dragged to reorder, and where every row sits (list coordinates).
    @State private var drag: TaskDrag?
    @State private var rowFrames: [TaskItem.ID: CGRect] = [:]
    /// The open editor's text field (list coordinates), where a drag selects text.
    @State private var editorFrame: CGRect?
    @State private var isFrosted = false
    @State private var isRevealed = false
    @FocusState private var field: Field?

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(palette.material)
                .overlay(palette.scrim)
                .mask(FrostSweep(progress: isFrosted ? 1 : 0, recedesToCenter: state.isDismissing))
                .ignoresSafeArea()
                // Clicking off a task ends its editing and goes back to "Add a task…".
                .onTapGesture(perform: state.focusInput)

            VStack(spacing: 20) {
                input
                    .opacity(isRevealed ? 1 : 0)
                    .offset(y: isRevealed ? 0 : -12)
                    .animation(contentAnimation, value: isRevealed)
                    .frame(width: Metrics.columnWidth)
                list
                    .frame(width: Metrics.columnWidth + Metrics.shadowRoom * 2)
            }
            .padding(.top, 96)

            corners
                .opacity(isRevealed ? 1 : 0)
                .animation(contentAnimation, value: isRevealed)
        }
        .onAppear {
            // Only on opening. Set again once the panel is key: during the first layout it doesn't
            // stick and the first keystroke would be lost.
            field = .input
            DispatchQueue.main.async { field = .input }
            withAnimation(Self.frostIn) { isFrosted = true }
            isRevealed = true
        }
        .onChange(of: state.isDismissing) { _, isDismissing in
            guard isDismissing else { return }
            field = nil
            isRevealed = false
            withAnimation(Self.frostOut) { isFrosted = false }
        }
        .onChange(of: state.focus) { _, focus in
            switch focus {
            case .input: field = .input
            case .task: field = nil
            case .editing:
                // The editor only exists after this update, so focus it on the next pass, then
                // put the caret at the end (a focused text field selects all by default).
                DispatchQueue.main.async {
                    field = .editor
                    DispatchQueue.main.async(execute: Self.moveCaretToEnd)
                }
            }
        }
        .onChange(of: field) { _, field in
            if field == .input, state.focus != .input { state.focusInput() }
        }
    }

    private var corners: some View {
        HStack {
            HStack(spacing: 6) {
                Text("esc")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.3)))
                Text("to close")
            }
            Spacer()
            if store.hasCompleted {
                Button("Clear completed") {
                    withAnimation(.spring(response: 0.3)) { store.clearCompleted() }
                }
                .buttonStyle(.plain)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .padding(24)
    }

    private var input: some View {
        HStack(spacing: 18) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.primary.opacity(0.5))
                .allowsHitTesting(false) // clicks on it reach the card below
            TextField("Add a task…", text: $state.draft)
                .textFieldStyle(.plain)
                .font(.system(size: 27))
                .focused($field, equals: .input)
                .onSubmit(add)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
        // A click anywhere on the card, not just on the text, starts typing.
        .background(
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .fill(palette.field)
                .onTapGesture { field = .input }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .strokeBorder(Color.primary.opacity(state.focus == .input ? 0.35 : 0.15))
        )
    }

    /// Runs to the bottom of the screen. Rows fade out under "Add a task…" when scrolled up,
    /// and gradually into the bottom edge.
    private var list: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    let rows = visibleRows
                    let subtaskCounts = store.subtaskCounts
                    LazyVStack(spacing: Metrics.rowSpacing) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, task in
                            TaskRow(
                                task: task,
                                stackedSubtasks: stackedSubtasks(of: task, counts: subtaskCounts),
                                hasSubtasks: subtaskCounts[task.id] != nil,
                                isSelected: state.selectedID == task.id,
                                isEditing: state.focus == .editing(task.id),
                                editText: $state.editText,
                                field: $field,
                                onToggle: { withAnimation(TaskRow.checkAnimation) { store.toggle(task.id) } },
                                onEdit: { state.beginEditing(task.id) },
                                onExpand: {
                                    withAnimation(.spring(response: 0.3)) { store.setCollapsed(task.id, false) }
                                },
                                onFold: {
                                    withAnimation(.spring(response: 0.3)) { store.setCollapsed(task.id, true) }
                                },
                                onDelete: { withAnimation(.spring(response: 0.3)) { store.delete(task.id) } }
                            )
                            .id(task.id)
                            .background(GeometryReader { geometry in
                                Color.clear.preference(key: RowFrames.self,
                                                       value: [task.id: geometry.frame(in: .named(Self.listSpace))])
                            })
                            // Drag to reorder, from anywhere on the card; while editing, a drag on the
                            // text selects it instead.
                            .gesture(reorderGesture(task.id))
                            // While dragged, the row itself rides above the list (below); its slot stays open,
                            // with a block beside it while it would land as a subtask.
                            .opacity(drag?.id == task.id ? 0 : 1)
                            .padding(.leading, task.isSubtask ? Metrics.indent : 0)
                            .overlay(alignment: .leading) {
                                if drag?.id == task.id, task.isSubtask {
                                    NestBlock(indent: Metrics.indent)
                                        .transition(.scale(scale: 0.4, anchor: .trailing).combined(with: .opacity))
                                }
                            }
                            .opacity(isRevealed ? 1 : 0)
                            .offset(y: isRevealed ? 0 : -14)
                            .animation(isRevealed ? Self.cascadeIn(index) : Self.cascadeOut(index, of: rows.count),
                                       value: isRevealed)
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    // Fills the visible list, so a click in the gaps or below the last task counts as
                    // a click off the task (the rows' own taps win over this).
                    .frame(minHeight: geometry.size.height - Metrics.topFade - Metrics.bottomFade, alignment: .top)
                    .background(Color.clear.contentShape(Rectangle()).onTapGesture(perform: state.focusInput))
                    .coordinateSpace(name: Self.listSpace)
                    .onPreferenceChange(RowFrames.self) { rowFrames = $0 }
                    .onPreferenceChange(EditorFrame.self) { editorFrame = $0 }
                    .overlay(alignment: .topLeading) { draggedRow }
                }
                .contentMargins(.horizontal, Metrics.shadowRoom, for: .scrollContent)
                .contentMargins(.top, Metrics.topFade, for: .scrollContent)
                .contentMargins(.bottom, Metrics.bottomFade, for: .scrollContent)
                .scrollIndicators(.never)
                .mask(fadeMask)
                .onChange(of: state.selectedID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id) }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    /// The focused text field's editor, caret moved after the last character.
    private static func moveCaretToEnd() {
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
    }

    // MARK: Reordering

    fileprivate static let listSpace = "taskList"

    /// The rows on screen; a dragged task's subtasks are tucked away while it moves.
    private var visibleRows: [TaskItem] {
        store.visibleTasks(dragging: drag?.id)
    }

    /// The dragged task follows the pointer; as its center passes a neighbor's middle, the list
    /// reorders (the neighbors slide), so the drop only has to settle it into its slot. Sideways,
    /// its left edge picks the level: past half an indent it's a subtask of the task above.
    private func reorderGesture(_ id: TaskItem.ID) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.listSpace))
            .onChanged { value in
                if drag == nil {
                    guard let frame = rowFrames[id] else { return }
                    if state.focus == .editing(id) {
                        if let editorFrame, editorFrame.contains(value.startLocation) { return }
                        // Picked up by the card: the edit is saved and the task moves.
                        state.commitEdit()
                    }
                    let started = TaskDrag(id: id, grab: value.startLocation.y - frame.minY, startLeft: frame.minX,
                                           top: frame.minY, left: frame.minX)
                    // Its subtasks fold away under it for the ride.
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { drag = started }
                }
                guard var current = drag, current.id == id, let frame = rowFrames[id] else { return }
                current.top = value.location.y - current.grab
                current.left = min(max(current.startLeft + value.translation.width, -Metrics.dragSlack),
                                   Metrics.indent + Metrics.dragSlack)
                drag = current
                reposition(current, height: frame.height)
            }
            .onEnded { _ in
                guard let frame = rowFrames[id] else {
                    drag = nil
                    return
                }
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    drag?.top = frame.minY
                    drag?.left = frame.minX
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    guard drag?.id == id else { return }
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        drag = nil
                        store.reveal(id)
                    }
                }
            }
    }

    /// Moves the dragged task one slot toward the pointer when it passes a neighbor, and sets its
    /// level from where its left edge is.
    private func reposition(_ drag: TaskDrag, height: CGFloat) {
        let ids = visibleRows.map(\.id)
        guard let position = ids.firstIndex(of: drag.id), let task = store.task(drag.id) else { return }
        var others = ids
        others.remove(at: position)

        // The slot is the gap in `others` it sits in.
        let center = drag.top + height / 2
        var slot = position
        if slot > 0, let above = rowFrames[others[slot - 1]], center < above.midY {
            slot -= 1
        } else if slot < others.count, let below = rowFrames[others[slot]], center > below.midY {
            slot += 1
        }

        // At the very top only a task. Dropped as a task among subtasks, it takes the ones below it;
        // as a subtask, a task's own subtasks come along and join the task above, as with Tab.
        let asSubtask = slot > 0 && drag.left > Metrics.indent / 2
        guard slot != position || asSubtask != task.isSubtask else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            store.place(drag.id, after: slot > 0 ? others[slot - 1] : nil, asSubtask: asSubtask)
        }
    }

    /// A collapsed task, or one being dragged, shows its subtasks as a stack under it.
    private func stackedSubtasks(of task: TaskItem, counts: [TaskItem.ID: Int]) -> Int {
        task.isCollapsed || drag?.id == task.id ? counts[task.id] ?? 0 : 0
    }

    /// The task being dragged, lifted above the list at the pointer. It takes on the look of the
    /// level it would land at.
    @ViewBuilder
    private var draggedRow: some View {
        if let drag, let task = store.task(drag.id), rowFrames[drag.id] != nil {
            TaskRow(task: task, stackedSubtasks: stackedSubtasks(of: task, counts: store.subtaskCounts),
                    hasSubtasks: false, isSelected: true, isEditing: false, editText: .constant(""), field: $field,
                    onToggle: {}, onEdit: {}, onExpand: {}, onFold: {}, onDelete: {})
                .frame(width: Metrics.columnWidth - (task.isSubtask ? Metrics.indent : 0))
                .scaleEffect(1.02)
                .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
                .offset(x: drag.left, y: drag.top)
                .allowsHitTesting(false)
        }
    }

    private var fadeMask: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: Metrics.topFade)
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: Metrics.bottomFade)
        }
    }

    private func add() {
        withAnimation(.spring(response: 0.3)) { store.add(state.draft) }
        state.draft = ""
    }
}

private struct TaskRow: View {
    let task: TaskItem
    /// Folded subtasks, drawn as a stack peeking out under the card.
    let stackedSubtasks: Int
    /// Has subtasks, so hovering shows a button to fold or unfold them.
    let hasSubtasks: Bool
    let isSelected: Bool
    let isEditing: Bool
    @Binding var editText: String
    var field: FocusState<TaskOverlayView.Field?>.Binding
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onExpand: () -> Void
    let onFold: () -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    /// Checking or unchecking: the checkmark and the row's resize run as one.
    static let checkAnimation = Animation.snappy(duration: 0.25, extraBounce: 0.15)

    init(task: TaskItem, stackedSubtasks: Int, hasSubtasks: Bool, isSelected: Bool, isEditing: Bool,
         editText: Binding<String>, field: FocusState<TaskOverlayView.Field?>.Binding,
         onToggle: @escaping () -> Void, onEdit: @escaping () -> Void, onExpand: @escaping () -> Void,
         onFold: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.task = task
        self.stackedSubtasks = stackedSubtasks
        self.hasSubtasks = hasSubtasks
        self.isSelected = isSelected
        self.isEditing = isEditing
        _editText = editText
        self.field = field
        self.onToggle = onToggle
        self.onEdit = onEdit
        self.onExpand = onExpand
        self.onFold = onFold
        self.onDelete = onDelete
    }

    /// Subtasks are a size down from tasks; done rows of either squeeze further, in the same
    /// animation as the checkmark.
    private var metrics: RowMetrics { RowMetrics(isSubtask: task.isSubtask, isCompact: task.isDone) }

    var body: some View {
        let palette = TaskPalette(scheme: colorScheme)
        let metrics = metrics
        HStack(spacing: metrics.spacing) {
            Button(action: onToggle) {
                // Sized by frame, not font, so it shrinks along with the row instead of jumping. The
                // fill scales in from the circle's center, and back into it when unchecked.
                ZStack {
                    Image(systemName: "circle")
                        .resizable()
                        .foregroundStyle(Color.secondary)
                        .opacity(task.isDone ? 0 : 1)
                    Image(systemName: "checkmark.circle.fill")
                        .resizable()
                        .foregroundStyle(Color.green)
                        .scaleEffect(task.isDone ? 1 : 0.2, anchor: .center)
                        .opacity(task.isDone ? 1 : 0)
                }
                .aspectRatio(contentMode: .fit)
                .frame(width: metrics.checkmark, height: metrics.checkmark)
            }
            .buttonStyle(.plain)

            Group {
                if isEditing {
                    // Wraps and grows so long tasks can be edited in full.
                    TextField("", text: $editText, prompt: Text("Add a task…"), axis: .vertical)
                        .lineLimit(1...8)
                        .textFieldStyle(.plain)
                        .focused(field, equals: .editor)
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: EditorFrame.self,
                                                   value: geometry.frame(in: .named(TaskOverlayView.listSpace)))
                        })
                } else {
                    Text(task.title)
                        .strikethrough(task.isDone)
                        .foregroundStyle(task.isDone ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onEdit)
                }
            }
            .font(.system(size: metrics.title))

            if hasSubtasks {
                let showsFold = isHovering
                Button(action: task.isCollapsed ? onExpand : onFold) {
                    Image(systemName: task.isCollapsed ? "rectangle.expand.vertical" : "rectangle.compress.vertical")
                        .font(.system(size: 17, weight: .medium))
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(task.isCollapsed ? "Unfold subtasks" : "Fold subtasks")
                .opacity(showsFold ? 1 : 0)
                .scaleEffect(showsFold ? 1 : 0.6)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: showsFold)
                .allowsHitTesting(showsFold)
            }

            let showsTrash = isEditing
            Button(action: onDelete) {
                Image(systemName: "trash.fill").font(.system(size: 18))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            // Pops in on hover rather than blinking on.
            .opacity(showsTrash ? 1 : 0)
            .scaleEffect(showsTrash ? 1 : 0.6)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: showsTrash)
            .allowsHitTesting(showsTrash)
        }
        .padding(.horizontal, metrics.horizontalPadding)
        // Done tasks squeeze down so they read as packed away.
        .padding(.vertical, metrics.verticalPadding)
        .background(
            // A click anywhere on the card edits the task (or keeps its editor focused).
            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .fill(isSelected ? palette.selectedCard : palette.card)
                .onTapGesture {
                    if isEditing { field.wrappedValue = .editor } else { onEdit() }
                }
                .shadow(color: isSelected ? palette.selectedShadow : .clear, radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .strokeBorder(isSelected ? palette.selectedBorder : .clear)
        )
        .padding(.bottom, CGFloat(min(stackedSubtasks, 2)) * SubtaskStack.layerPeek)
        .background {
            // A click on the stack unfolds it.
            let layers = min(stackedSubtasks, 2)
            SubtaskStack(layers: layers, cornerRadius: metrics.cornerRadius, fill: palette.card)
                .contentShape(SubtaskStack.Peek(layers: layers, cornerRadius: metrics.cornerRadius))
                .onTapGesture(perform: onExpand)
        }
        .onHover { isHovering = $0 }
    }
}

private struct RowMetrics {
    let isSubtask: Bool
    let isCompact: Bool

    var checkmark: CGFloat { isSubtask ? (isCompact ? 17 : 22) : (isCompact ? 20 : 28) }
    var title: CGFloat { isSubtask ? (isCompact ? 15 : 18) : (isCompact ? 16 : 22) }
    var spacing: CGFloat { isSubtask ? 14 : 18 }
    var horizontalPadding: CGFloat { isSubtask ? 20 : 24 }
    var verticalPadding: CGFloat { isSubtask ? (isCompact ? 5 : 13) : (isCompact ? 6 : 19) }
    var cornerRadius: CGFloat { isSubtask ? 15 : 18 }
}

/// A task being dragged, in list coordinates: `grab` is where the pointer holds it (from the row's
/// top), `top` and `left` where the lifted row is drawn, `startLeft` where it was picked up.
private struct TaskDrag: Equatable {
    let id: TaskItem.ID
    let grab: CGFloat
    let startLeft: CGFloat
    var top: CGFloat
    var left: CGFloat
}

/// Beside the open slot of the row being dragged while it would land as a subtask, in the indent.
private struct NestBlock: View {
    let indent: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.primary.opacity(0.22))
            .frame(width: 12)
            .padding(.vertical, 4)
            .frame(width: indent)
            .allowsHitTesting(false)
    }
}

/// Folded subtasks: up to two cards peeking out under the task's card, each a little narrower.
/// Fills the row, card and peek together. Only the peeking edges are drawn, so the translucent
/// cards don't darken the one on top.
private struct SubtaskStack: View {
    static let layerPeek: CGFloat = 6
    static let layerInset: CGFloat = 14

    let layers: Int
    let cornerRadius: CGFloat
    let fill: Color

    var body: some View {
        ZStack {
            ForEach(0..<layers, id: \.self) { layer in
                Peek(layers: layers, cornerRadius: cornerRadius, only: layer + 1)
                    .fill(fill.opacity(layer == 0 ? 1 : 0.6))
            }
        }
        .allowsHitTesting(layers > 0)
    }

    /// The stack's peeking edges in a row `rect` whose card is the top part; `only` keeps one layer.
    struct Peek: Shape {
        let layers: Int
        let cornerRadius: CGFloat
        var only: Int?

        func path(in rect: CGRect) -> Path {
            guard layers > 0 else { return Path() }
            var card = rect
            card.size.height -= CGFloat(layers) * SubtaskStack.layerPeek
            var covered = Path(roundedRect: card, cornerRadius: cornerRadius, style: .continuous)
            var result = Path()
            for layer in 1...layers {
                let shape = Path(roundedRect: card
                    .insetBy(dx: CGFloat(layer) * SubtaskStack.layerInset, dy: 0)
                    .offsetBy(dx: 0, dy: CGFloat(layer) * SubtaskStack.layerPeek),
                    cornerRadius: cornerRadius, style: .continuous)
                if only == nil || only == layer { result.addPath(shape.subtracting(covered)) }
                covered = covered.union(shape)
            }
            return result
        }
    }
}

private struct EditorFrame: PreferenceKey {
    static let defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

private struct RowFrames: PreferenceKey {
    static let defaultValue: [TaskItem.ID: CGRect] = [:]

    static func reduce(value: inout [TaskItem.ID: CGRect], nextValue: () -> [TaskItem.ID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Light mode uses a bright frosted material with white cards; the selected card is the lightest.
private struct TaskPalette {
    let scheme: ColorScheme
    private var isDark: Bool { scheme == .dark }

    var material: Material { isDark ? .ultraThinMaterial : .regularMaterial }
    var scrim: Color { isDark ? .black.opacity(0.4) : .white.opacity(0.45) }
    var field: Color { isDark ? .white.opacity(0.14) : .white.opacity(0.75) }
    var card: Color { isDark ? .white.opacity(0.06) : .white.opacity(0.5) }
    var selectedCard: Color { isDark ? .white.opacity(0.16) : .white }
    var selectedBorder: Color { isDark ? .white.opacity(0.3) : .black.opacity(0.06) }
    var selectedShadow: Color { isDark ? .clear : .black.opacity(0.08) }
}

/// Frost reveal mask, drawn by the `frostMask` shader (Shaders/FrostShader.metal): the screen frosts
/// unevenly, patch by patch, following fractal noise, with the edges leading slightly.
/// `progress` is how much frost is showing; closing plays it back with the edges clearing first.
struct FrostSweep: View, Animatable {
    var progress: CGFloat
    var recedesToCenter = false

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    /// New pattern each time the overlay opens (the view is rebuilt per opening).
    @State private var seed = Float.random(in: 0...100)

    var body: some View {
        let tuning = ShaderTuning.values
        GeometryReader { geometry in
            Rectangle()
                .fill(.black)
                .colorEffect(ShaderLibrary.frostMask(
                    .float2(geometry.size),
                    .float(Float(progress)),
                    .float(Float(tuning.frostEdgeBias)),
                    .float(recedesToCenter ? 1 : 0),
                    .float(seed),
                    .float(Float(tuning.frostScale)),
                    .float(Float(tuning.frostOctaves)),
                    .float(Float(tuning.frostSoft))
                ))
        }
    }
}
