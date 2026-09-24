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

    private(set) var isVisible = false

    init(onVisibilityChange: @escaping (Bool) -> Void) {
        self.onVisibilityChange = onVisibilityChange
        panel.onCancel = { [weak self] in self?.hide() }
    }

    func show() {
        guard !isVisible, let screen = NSScreen.underMouse else { return }
        panel.setFrame(screen.frame, display: false)
        // nil follows the system's light/dark appearance.
        panel.appearance = TaskAppearance.isAlwaysDark ? NSAppearance(named: .darkAqua) : nil
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
        isVisible = true
        onVisibilityChange(true)
    }

    /// Plays the reveal backwards, then removes the panel. Every way of closing ends up here.
    func hide() {
        guard isVisible, let state, !state.isDismissing else { return }
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        state.isDismissing = true
        onVisibilityChange(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + TaskOverlayView.exitDuration) { [weak self] in
            self?.finishHiding()
        }
    }

    private func finishHiding() {
        panel.orderOut(nil)
        panel.contentView = nil
        state = nil
        isVisible = false
    }
}

/// Tasks follow the system appearance unless "Always Dark Tasks" is on (menu bar menu).
enum TaskAppearance {
    private static let alwaysDarkKey = "tasks.alwaysDark"

    static var isAlwaysDark: Bool {
        get { UserDefaults.standard.bool(forKey: alwaysDarkKey) }
        set { UserDefaults.standard.set(newValue, forKey: alwaysDarkKey) }
    }
}

/// Keyboard selection and inline editing. ↑/↓ move between "Add a task…" and the tasks,
/// Return (or a click) edits the selected task, Return saves, Esc cancels the edit or closes.
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
            case .editing: commitEdit()
            }
            return .handled
        case kVK_Escape:
            if case .editing = focus {
                cancelEdit()
                return .handled
            }
            return .close
        default:
            return .ignored
        }
    }

    func beginEditing(_ id: TaskItem.ID) {
        commitEdit()
        guard let task = store.tasks.first(where: { $0.id == id }) else { return }
        editText = task.title
        focus = .editing(id)
    }

    func commitEdit() {
        guard case .editing(let id) = focus else { return }
        store.rename(id, to: editText)
        focus = .task(id)
    }

    func focusInput() {
        commitEdit()
        focus = .input
    }

    private func cancelEdit() {
        guard case .editing(let id) = focus else { return }
        focus = .task(id)
    }

    private func move(by step: Int) -> KeyResult {
        let ids = store.tasks.map(\.id)
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
        /// Room beside the rows so the selected card's shadow isn't clipped by the scroll view.
        static let shadowRoom: CGFloat = 20
        static let topFade: CGFloat = 28
        static let bottomFade: CGFloat = 240
    }

    // Entering: frost, field and the task cascade all start together.
    // Exiting plays it backwards: tasks leave bottom-up, then the field, then the frost
    // clears from the edges into the middle.
    /// Frost timings (Shader Lab). Everything else is timed around them.
    private static var frostInDuration: TimeInterval { ShaderTuning.shared.values.frostInDuration }
    private static var frostOutDuration: TimeInterval { ShaderTuning.shared.values.frostOutDuration }
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

    @State private var draft = ""
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
                // The editor only exists after this update, so focus it on the next pass.
                DispatchQueue.main.async { field = .editor }
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
            TextField("Add a task…", text: $draft)
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
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(Array(store.tasks.enumerated()), id: \.element.id) { index, task in
                        TaskRow(
                            task: task,
                            isSelected: state.selectedID == task.id,
                            isEditing: state.focus == .editing(task.id),
                            editText: $state.editText,
                            field: $field,
                            onToggle: { withAnimation(.spring(response: 0.3)) { store.toggle(task.id) } },
                            onEdit: { state.beginEditing(task.id) },
                            onDelete: { withAnimation(.spring(response: 0.3)) { store.delete(task.id) } }
                        )
                        .id(task.id)
                        .opacity(isRevealed ? 1 : 0)
                        .offset(y: isRevealed ? 0 : -14)
                        .animation(isRevealed ? Self.cascadeIn(index) : Self.cascadeOut(index, of: store.tasks.count),
                                   value: isRevealed)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
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
        .frame(maxHeight: .infinity)
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
        withAnimation(.spring(response: 0.3)) { store.add(draft) }
        draft = ""
    }
}

private struct TaskRow: View {
    let task: TaskItem
    let isSelected: Bool
    let isEditing: Bool
    @Binding var editText: String
    var field: FocusState<TaskOverlayView.Field?>.Binding
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    /// Done tasks squeeze down, but only after the checkmark has landed so the two don't fight.
    @State private var isCompact: Bool

    /// How long the checkmark plays at full size before the row squeezes.
    private static let compactDelay: Duration = .milliseconds(350)

    init(task: TaskItem, isSelected: Bool, isEditing: Bool, editText: Binding<String>,
         field: FocusState<TaskOverlayView.Field?>.Binding,
         onToggle: @escaping () -> Void, onEdit: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.task = task
        self.isSelected = isSelected
        self.isEditing = isEditing
        _editText = editText
        self.field = field
        self.onToggle = onToggle
        self.onEdit = onEdit
        self.onDelete = onDelete
        _isCompact = State(initialValue: task.isDone)
    }

    var body: some View {
        let palette = TaskPalette(scheme: colorScheme)
        HStack(spacing: 18) {
            Button(action: onToggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .contentTransition(.symbolEffect(.replace))
                    .font(.system(size: isCompact ? 20 : 28))
                    .foregroundStyle(task.isDone ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)

            Group {
                if isEditing {
                    // Wraps and grows so long tasks can be edited in full.
                    TextField("", text: $editText, axis: .vertical)
                        .lineLimit(1...8)
                        .textFieldStyle(.plain)
                        .focused(field, equals: .editor)
                } else {
                    Text(task.title)
                        .strikethrough(task.isDone)
                        .foregroundStyle(task.isDone ? .secondary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onEdit)
                }
            }
            .font(.system(size: isCompact ? 16 : 22))

            Button(action: onDelete) {
                Image(systemName: "trash").font(.system(size: 18))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(isHovering || isEditing ? 1 : 0)
        }
        .padding(.horizontal, 24)
        // Done tasks squeeze down so they read as packed away.
        .padding(.vertical, isCompact ? 6 : 19)
        .background(
            // A click anywhere on the card edits the task (or keeps its editor focused).
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isSelected ? palette.selectedCard : palette.card)
                .onTapGesture {
                    if isEditing { field.wrappedValue = .editor } else { onEdit() }
                }
                .shadow(color: isSelected ? palette.selectedShadow : .clear, radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isSelected ? palette.selectedBorder : .clear)
        )
        .onHover { isHovering = $0 }
        .task(id: task.isDone) {
            guard task.isDone != isCompact else { return }
            if task.isDone { try? await Task.sleep(for: Self.compactDelay) }
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { isCompact = task.isDone }
        }
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
        let tuning = ShaderTuning.shared.values
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
