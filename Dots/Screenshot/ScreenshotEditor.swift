import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The shot being framed, its marks and the frame's style; and the copy and save that
/// render it (FramedShot at the shot's own resolution, effects frozen as they are on screen).
@MainActor
final class ScreenshotEditorModel: ObservableObject {
    /// nil until there's a shot: no Screen Recording permission yet, or the capture failed.
    @Published private(set) var shot: ScreenCapture.Shot?
    @Published var style = FrameStyle.saved {
        didSet { style.save() }
    }
    @Published private(set) var marks: [Mark] = []
    @Published var tool = Mark.Kind.arrow
    @Published private(set) var ink = Mark.Ink.color(.red)
    @Published var isDismissing = false
    @Published var error: String?
    /// "Copied", "Saved": a moment's confirmation over the buttons.
    @Published private(set) var toast: String?
    /// Shader effects animate against this.
    let startDate = Date()
    private var history: [[Mark]] = []
    private var isDrawing = false
    private var toastID = UUID()

    init(shot: ScreenCapture.Shot?) {
        self.shot = shot
    }

    func replace(_ shot: ScreenCapture.Shot) {
        self.shot = shot
        marks = []
        history = []
        error = nil
    }

    /// The shot's size in canvas points (FramedShot.canvasScale).
    var shotSize: CGSize {
        guard let shot else { return .zero }
        let scale = FramedShot.canvasScale(for: shot.size)
        return CGSize(width: shot.size.width * scale, height: shot.size.height * scale)
    }

    var canUndo: Bool { !history.isEmpty }
    /// While a shader is on screen the stage ticks every frame; otherwise it holds still.
    var animates: Bool {
        style.edge != .none || marks.contains { if case .effect = $0.ink { true } else { false } }
    }

    // MARK: Marks

    func pick(_ ink: Mark.Ink) {
        if case .effect = ink, !ProStore.shared.isPro {
            UnlockController.shared.show(for: .brushes)
            return
        }
        self.ink = ink
    }

    func setEdge(_ edge: EdgeEffect) {
        guard !edge.isPro || ProStore.shared.isPro else {
            UnlockController.shared.show(for: .cameraEffects)
            return
        }
        style.edge = edge
    }

    /// `point` from the shot's top-left, in canvas points. Called on every move of a drag; only its
    /// first starts a mark.
    func begin(at point: CGPoint) {
        guard !isDrawing else { return }
        history.append(marks)
        marks.append(Mark(kind: tool, ink: ink, points: tool == .pen ? [point] : [point, point]))
        isDrawing = true
    }

    func extend(to point: CGPoint) {
        guard isDrawing, let last = marks.last?.points.last else { return }
        let index = marks.count - 1
        if marks[index].kind == .pen {
            guard hypot(point.x - last.x, point.y - last.y) >= 1 else { return }
            marks[index].points.append(point)
        } else {
            marks[index].points[1] = point
        }
    }

    /// An arrow or a box that's a click rather than a drag is dropped.
    func end() {
        guard isDrawing, let last = marks.last, let start = last.points.first, let end = last.points.last else { return }
        isDrawing = false
        if last.kind != .pen, hypot(end.x - start.x, end.y - start.y) < 6 {
            marks.removeLast()
            history.removeLast()
        }
    }

    func undo() {
        guard let previous = history.popLast() else { return }
        withAnimation(.easeOut(duration: 0.15)) { marks = previous }
    }

    func clearMarks() {
        guard !marks.isEmpty else { return }
        history.append(marks)
        withAnimation(.easeOut(duration: 0.15)) { marks = [] }
    }

    // MARK: Output

    /// The framed shot at the shot's own resolution: a full Retina screen stays full Retina.
    func render() -> CGImage? {
        guard let shot else { return nil }
        let renderer = ImageRenderer(content: FramedShot(
            image: shot.image, shotSize: shotSize, style: style, marks: marks,
            time: Date().timeIntervalSince(startDate)
        ))
        renderer.scale = shot.scale / FramedShot.canvasScale(for: shot.size)
        return renderer.cgImage
    }

    private func pngData() -> Data? {
        render().flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
    }

    /// PNG, so a clear background stays clear; TIFF too, for apps that only take that.
    @discardableResult
    func copy() -> Bool {
        guard let image = render(), let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { return false }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        if let tiff = NSImage(cgImage: image, size: .zero).tiffRepresentation {
            pasteboard.setData(tiff, forType: .tiff)
        }
        show(toast: "Copied")
        return true
    }

    /// As a sheet on the editor, so it opens over it rather than behind.
    func save(over window: NSWindow) {
        guard shot != nil, window.attachedSheet == nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = Self.fileName()
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { [weak self] response in
            MainActor.assumeIsolated {
                guard let self, response == .OK, let url = panel.url, let data = self.pngData() else { return }
                do {
                    try data.write(to: url)
                    self.show(toast: "Saved")
                } catch {
                    Log.screenshot.error("Save failed: \(error.localizedDescription, privacy: .public)")
                    self.show(toast: "Couldn't save it there")
                }
            }
        }
    }

    /// ⌘V: frames the image on the clipboard instead, e.g. one taken with the system's shortcuts.
    func pasteImage() {
        guard let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage else {
            show(toast: "No image on the clipboard")
            return
        }
        load(image)
    }

    /// An image file or image dropped on the editor.
    func load(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSImage.self) }) else { return false }
        _ = provider.loadObject(ofClass: NSImage.self) { [weak self] object, _ in
            guard let image = object as? NSImage else { return }
            Task { @MainActor in self?.load(image) }
        }
        return true
    }

    private func load(_ image: NSImage) {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil), image.size.width > 0 else { return }
        replace(ScreenCapture.Shot(image: cgImage, scale: max(1, CGFloat(cgImage.width) / image.size.width)))
    }

    private func show(toast message: String) {
        let id = UUID()
        toastID = id
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { toast = message }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            guard let self, self.toastID == id else { return }
            withAnimation(.easeIn(duration: 0.2)) { self.toast = nil }
        }
    }

    /// Like the system's: "Screenshot 2026-10-01 at 14.03.22.png".
    private static func fileName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Screenshot \(formatter.string(from: Date())).png"
    }
}

/// In its own window (ScreenshotController): the mark tools on top, the framed shot in the middle
/// (drawn on directly), the frame's settings on the right and copy and save below.
struct ScreenshotEditor: View {
    static let exitDuration: TimeInterval = 0.25
    /// Room for the window's traffic lights above the toolbar.
    private static let topInset: CGFloat = 40

    @ObservedObject var model: ScreenshotEditorModel
    let onRetake: () -> Void
    let onSave: () -> Void
    let onCopy: () -> Void

    @State private var isRevealed = false

    var body: some View {
        ZStack {
            WindowBackdrop()

            HStack(alignment: .top, spacing: 24) {
                VStack(spacing: 20) {
                    // Nothing to draw on yet: the empty stage has the toolbar's height to itself.
                    if model.shot != nil {
                        MarkToolbar(model: model)
                            .modifier(Reveal(isRevealed: isRevealed, step: 0))
                    }
                    stage
                        .modifier(Reveal(isRevealed: isRevealed, step: 1))
                    // Without a shot, the empty stage has its own buttons.
                    if model.shot != nil {
                        actions
                            .modifier(Reveal(isRevealed: isRevealed, step: 2))
                    }
                }
                FrameInspector(model: model)
                    .frame(width: 268)
                    .modifier(Reveal(isRevealed: isRevealed, step: 1))
            }
            .padding(.top, Self.topInset)
            .padding([.horizontal, .bottom], 24)
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .onDrop(of: [.image, .fileURL], isTargeted: nil) { model.load($0) }
        .onAppear { isRevealed = true }
    }

    // MARK: Stage

    private var stage: some View {
        GeometryReader { geometry in
            Group {
                if let shot = model.shot {
                    canvas(shot, fitting: geometry.size)
                } else {
                    EmptyStage(error: model.error, onRetake: onRetake, onPaste: model.pasteImage)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func canvas(_ shot: ScreenCapture.Shot, fitting area: CGSize) -> some View {
        let layout = FramedShot.layout(shotSize: model.shotSize, style: model.style)
        let fit = min(1, area.width / layout.canvas.width, area.height / layout.canvas.height)
        let origin = layout.content.origin
        func local(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x - origin.x, y: point.y - origin.y) }
        return ZStack {
            if model.style.background == .clear {
                Checkerboard()
            }
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !model.animates)) { timeline in
                FramedShot(image: shot.image, shotSize: model.shotSize, style: model.style, marks: model.marks,
                           time: timeline.date.timeIntervalSince(model.startDate))
            }
        }
        .frame(width: layout.canvas.width, height: layout.canvas.height)
        .contentShape(Rectangle())
        // Before the scale, so the drag reports canvas points.
        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                model.begin(at: local(value.startLocation))
                model.extend(to: local(value.location))
            }
            .onEnded { _ in model.end() })
        .onContinuousHover { phase in
            if case .active = phase { NSCursor.crosshair.set() } else { NSCursor.arrow.set() }
        }
        .scaleEffect(fit)
        .frame(width: layout.canvas.width * fit, height: layout.canvas.height * fit)
        .shadow(color: .black.opacity(0.35), radius: 30, y: 14)
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: model.style)
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: onRetake) {
                Label("New shot", systemImage: "camera.viewfinder")
            }
            .buttonStyle(EditorButtonStyle())
            .help("Take another screenshot  ⌘N")
            Button(action: onSave) {
                Label("Save…", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(EditorButtonStyle())
            .help("Save as PNG  ⌘S")
            Button(action: onCopy) {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(EditorButtonStyle(isProminent: true))
            .help("Copy and close  ⌘C")
        }
        .overlay(alignment: .top) {
            if let toast = model.toast {
                Text(toast)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.white.opacity(0.18)))
                    .fixedSize()
                    .offset(y: -42)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
    }
}

/// The window's frosted, dark glass: the desktop blurred behind it, like a HUD.
private struct WindowBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Fades and rises into place, one part after another.
private struct Reveal: ViewModifier {
    let isRevealed: Bool
    let step: Int

    func body(content: Content) -> some View {
        content
            .opacity(isRevealed ? 1 : 0)
            .offset(y: isRevealed ? 0 : 20)
            .animation(isRevealed ? .spring(response: 0.45, dampingFraction: 0.85).delay(0.12 + Double(step) * 0.05)
                                  : .easeIn(duration: 0.18),
                       value: isRevealed)
    }
}

/// No shot yet: why, and how to get one.
private struct EmptyStage: View {
    let error: String?
    let onRetake: () -> Void
    let onPaste: () -> Void

    var body: some View {
        let hasPermission = ScreenCapture.hasPermission
        VStack(spacing: 12) {
            Image(systemName: hasPermission ? "camera.viewfinder" : "lock.rectangle.on.rectangle")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Dot.screenshot.tint)
            Text(hasPermission ? (error == nil ? "Frame a screenshot" : "Couldn't take the screenshot")
                               : "Let Dots see your screen")
                .font(.system(size: 20, weight: .semibold))
            Text(message(hasPermission: hasPermission))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            HStack(spacing: 8) {
                if !hasPermission {
                    Button("Open Settings", action: ScreenCapture.openPrivacySettings)
                        .buttonStyle(EditorButtonStyle(isProminent: true))
                }
                Button("Take a screenshot", action: onRetake)
                    .buttonStyle(EditorButtonStyle(isProminent: hasPermission))
                Button("Paste an image", action: onPaste)
                    .buttonStyle(EditorButtonStyle())
            }
            .padding(.top, 8)
        }
        .padding(32)
        .background(RoundedRectangle(cornerRadius: EditorMetrics.cardRadius, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private func message(hasPermission: Bool) -> String {
        if !hasPermission {
            return "Turn on Dots in System Settings › Privacy & Security › Screen Recording. macOS may ask to reopen Dots. "
                + "You can also paste an image (⌘V) or drop one here."
        }
        return error ?? "Take one, paste an image (⌘V) or drop one here."
    }
}

/// A transparent background shows through as the usual checkerboard; it isn't part of the export.
private struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let square: CGFloat = 12
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.85)))
            for row in 0..<Int(ceil(size.height / square)) {
                for column in 0..<Int(ceil(size.width / square)) where (row + column).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: CGFloat(column) * square, y: CGFloat(row) * square,
                                             width: square, height: square)), with: .color(Color(white: 0.7)))
                }
            }
        }
    }
}

// MARK: - Metrics

/// Shared sizes, so radii nest (outer = inner + padding) and cards match.
private enum EditorMetrics {
    /// The inspector and the empty stage.
    static let cardRadius: CGFloat = 24
    static let cardPadding: CGFloat = 16
    /// Swatches inside a card: its radius less its padding.
    static let swatchRadius = cardRadius - cardPadding
    static let swatch: CGFloat = 32
    /// Selection rings sit this far outside what they ring, with the radius grown to match.
    static let ringGap: CGFloat = 3
    /// Every toolbar button is this square.
    static let toolCell: CGFloat = 32
    static let toolbarPadding: CGFloat = 6
    /// SF Symbols at one weight, so strokes match across the editor.
    static let glyphWeight = Font.Weight.medium
}

// MARK: - Toolbar

/// Pen, arrow, box; the colors and the pen's shader inks; undo and clear. A capsule, so the selected
/// tool's highlight is a circle: the capsule's radius less its padding is half a cell.
private struct MarkToolbar: View {
    @ObservedObject var model: ScreenshotEditorModel
    @ObservedObject private var pro = ProStore.shared

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Mark.Kind.allCases, id: \.self) { kind in
                Button { model.tool = kind } label: {
                    Image(systemName: kind.symbol)
                        .frame(width: EditorMetrics.toolCell, height: EditorMetrics.toolCell)
                        .background(Circle().fill(Color.white.opacity(model.tool == kind ? 0.2 : 0)))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("\(kind.title)  \(kind.key.uppercased())")
            }
            divider
            ForEach(MarkColor.allCases) { color in
                swatch(AnyShapeStyle(color.color), isSelected: model.ink == .color(color), isLocked: false) {
                    model.pick(.color(color))
                }
                .help(color.rawValue.capitalized)
            }
            divider
            ForEach([Brush.electric, .fire, .rainbow]) { brush in
                swatch(brush.swatch, isSelected: model.ink == .effect(brush), isLocked: !pro.isPro) {
                    model.pick(.effect(brush))
                }
                .help(pro.isPro ? "\(brush.title) ink" : "\(brush.title) ink (Dots Pro)")
            }
            divider
            glyphButton("arrow.uturn.backward", isEnabled: model.canUndo, action: model.undo)
                .help("Undo  ⌘Z")
            glyphButton("trash", isEnabled: !model.marks.isEmpty, action: model.clearMarks)
                .help("Clear the drawing")
        }
        .font(.system(size: 15, weight: EditorMetrics.glyphWeight))
        .foregroundStyle(.white.opacity(0.9))
        .padding(EditorMetrics.toolbarPadding)
        .background(Capsule().fill(.ultraThinMaterial))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 20).padding(.horizontal, 4)
    }

    private func glyphButton(_ symbol: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: EditorMetrics.toolCell, height: EditorMetrics.toolCell)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
    }

    private func swatch(_ fill: AnyShapeStyle, isSelected: Bool, isLocked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(fill)
                // Enough of a rim that black still shows on the dark toolbar.
                .overlay(Circle().strokeBorder(Color.white.opacity(0.3), lineWidth: 1))
                .frame(width: 20, height: 20)
                .overlay(Circle().strokeBorder(Color.white, lineWidth: isSelected ? 2 : 0).padding(-4))
                .overlay(alignment: .bottomTrailing) {
                    if isLocked { LockBadge().offset(x: 4, y: 4) }
                }
                .frame(width: EditorMetrics.toolCell, height: EditorMetrics.toolCell)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Inspector

/// The frame's settings, remembered for the next shot.
private struct FrameInspector: View {
    @ObservedObject var model: ScreenshotEditorModel
    @ObservedObject private var pro = ProStore.shared

    var body: some View {
        let card = RoundedRectangle(cornerRadius: EditorMetrics.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 16) {
            Text("Frame").font(.system(size: 15, weight: .semibold))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    section("Background") { backgrounds }
                    slider("Padding", value: $model.style.padding, in: 0...160) { "\(Int($0))" }
                    slider("Corners", value: $model.style.cornerRadius, in: 0...40) { "\(Int($0))" }
                    slider("Shadow", value: $model.style.shadow, in: 0...1) { "\(Int(($0 * 100).rounded()))%" }
                    section("Shape") {
                        segmented(selection: $model.style.aspect, options: FrameAspect.allCases, title: \.title)
                    }
                    section("Title bar") {
                        segmented(selection: $model.style.chrome, options: WindowChrome.allCases, title: \.title)
                        if model.style.chrome == .safari {
                            TextField("Address, e.g. dots.app", text: $model.style.address)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                                .padding(.horizontal, 8)
                                .frame(height: 28)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.08)))
                        }
                    }
                    section("Edge") { edges }
                }
                // Room for the selection rings, which sit outside the swatches; the scroll view clips.
                .padding(EditorMetrics.ringGap + 1)
            }
            .padding(-(EditorMetrics.ringGap + 1))
        }
        .padding(EditorMetrics.cardPadding)
        .background(card.fill(.ultraThinMaterial))
        .overlay(card.strokeBorder(Color.white.opacity(0.1)))
        .fixedSize(horizontal: false, vertical: true)
        .disabled(model.isDismissing)
    }

    private func section(_ title: String, value: String? = nil, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .foregroundStyle(.secondary)
                Spacer()
                if let value {
                    Text(value)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.system(size: 12, weight: .medium))
            content()
        }
    }

    private func slider(_ title: String, value: Binding<CGFloat>, in range: ClosedRange<CGFloat>,
                        format: (CGFloat) -> String) -> some View {
        section(title, value: format(value.wrappedValue)) {
            Slider(value: value, in: range)
                .controlSize(.small)
                .tint(Dot.screenshot.tint)
        }
    }

    /// Full width with equal segments, so every row lines up with the sliders (the system's
    /// segmented control sizes to its titles). The thumb's radius is the track's less its inset.
    private func segmented<Option: Hashable & Identifiable>(selection: Binding<Option>, options: [Option],
                                                            title: KeyPath<Option, String>) -> some View {
        let inset: CGFloat = 2
        let radius: CGFloat = 8
        return HStack(spacing: 0) {
            ForEach(options) { option in
                let isSelected = selection.wrappedValue == option
                Button { selection.wrappedValue = option } label: {
                    Text(option[keyPath: title])
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: radius - inset, style: .continuous)
                                    .fill(Color.white.opacity(0.2))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(inset)
        .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.white.opacity(0.08)))
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: selection.wrappedValue)
    }

    /// The presets, then your color: picking it opens the system color panel.
    private var backgrounds: some View {
        let columns = Array(repeating: GridItem(.fixed(EditorMetrics.swatch), spacing: 8), count: 6)
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(FrameBackground.allCases) { background in
                Button { pick(background) } label: {
                    BackgroundSwatch(background: background, style: model.style, shot: model.shot?.image)
                        .frame(width: EditorMetrics.swatch, height: EditorMetrics.swatch)
                        .overlay(SelectionRing(isSelected: model.style.background == background))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(background.title)
            }
        }
    }

    private func pick(_ background: FrameBackground) {
        model.style.background = background
        guard background == .custom else { return }
        ColorWell.shared.open(color: NSColor(model.style.customColor.color)) { [weak model] color in
            model?.style.customColor = RGBA(color)
            model?.style.background = .custom
        }
    }

    private var edges: some View {
        HStack(spacing: 4) {
            ForEach(EdgeEffect.allCases) { edge in
                Button { model.setEdge(edge) } label: {
                    VStack(spacing: 4) {
                        Circle()
                            .fill(edge.swatch)
                            .overlay {
                                if edge == .none {
                                    Image(systemName: "nosign")
                                        .font(.system(size: 12, weight: EditorMetrics.glyphWeight))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 28, height: 28)
                            .overlay(Circle().strokeBorder(Color.white, lineWidth: model.style.edge == edge ? 2 : 0).padding(-4))
                            .overlay(alignment: .bottomTrailing) {
                                if edge.isPro, !pro.isPro { LockBadge().offset(x: 4, y: 4) }
                            }
                        Text(edge.title)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                            .fixedSize()
                            .foregroundStyle(model.style.edge == edge ? .primary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(edge.isPro && !pro.isPro ? "\(edge.title) (Dots Pro)" : edge.title)
            }
        }
    }
}

/// Around a swatch, `ringGap` out, its radius grown by the same so the curves stay parallel.
private struct SelectionRing: View {
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: EditorMetrics.swatchRadius + EditorMetrics.ringGap, style: .continuous)
            .strokeBorder(Color.white, lineWidth: isSelected ? 2 : 0)
            .padding(-EditorMetrics.ringGap)
    }
}

private struct BackgroundSwatch: View {
    let background: FrameBackground
    let style: FrameStyle
    let shot: CGImage?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: EditorMetrics.swatchRadius, style: .continuous)
        Group {
            switch background {
            case .clear:
                Checkerboard()
            case .custom:
                style.customColor.color
                    .overlay(
                        Image(systemName: "eyedropper")
                            .font(.system(size: 13, weight: EditorMetrics.glyphWeight))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.4), radius: 1)
                    )
            case .blur:
                if let shot {
                    // In an overlay, so filling doesn't make the swatch wider than its square.
                    Color.clear.overlay {
                        Image(decorative: shot, scale: 1).resizable().scaledToFill().blur(radius: 4).saturation(1.3)
                    }
                } else {
                    Color.gray
                }
            default:
                LinearGradient(colors: background.colors ?? [], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5))
    }
}

/// "Your color" opens the system color panel over the editor; its picks come back live.
@MainActor
final class ColorWell: NSObject {
    static let shared = ColorWell()

    private var onChange: ((NSColor) -> Void)?

    func open(color: NSColor, onChange: @escaping (NSColor) -> Void) {
        let panel = NSColorPanel.shared
        // Before the target, so setting it doesn't report back as a pick.
        self.onChange = nil
        panel.showsAlpha = false
        panel.color = color
        panel.setTarget(self)
        panel.setAction(#selector(changed(_:)))
        panel.isContinuous = true
        panel.level = DotsLevel.unlock
        panel.orderFront(nil)
        self.onChange = onChange
    }

    func close() {
        onChange = nil
        guard NSColorPanel.sharedColorPanelExists else { return }
        NSColorPanel.shared.setTarget(nil)
        NSColorPanel.shared.orderOut(nil)
    }

    @objc private func changed(_ sender: NSColorPanel) {
        onChange?(sender.color)
    }
}

/// Marks a Dots Pro choice.
private struct LockBadge: View {
    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 14, height: 14)
            .background(Circle().fill(Color.black.opacity(0.65)))
    }
}

// MARK: - Buttons

private struct EditorButtonStyle: ButtonStyle {
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(EditorLabelStyle())
            .modifier(EditorButtonLook(isProminent: isProminent, isPressed: configuration.isPressed))
    }
}

private struct EditorLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
            configuration.title
        }
    }
}

private struct EditorButtonLook: ViewModifier {
    let isProminent: Bool
    let isPressed: Bool
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Capsule().fill(isProminent ? Dot.screenshot.tint : Color.white.opacity(0.12)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(isProminent ? 0 : 0.08)))
            .opacity(isEnabled ? (isPressed ? 0.8 : 1) : 0.4)
            .scaleEffect(isPressed ? 0.97 : 1)
            .contentShape(Capsule())
    }
}
