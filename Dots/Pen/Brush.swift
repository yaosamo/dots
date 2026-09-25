import AppKit
import SwiftUI

enum Brush: String, CaseIterable, Identifiable, Codable {
    case ink, electric, fire, rainbow, spotlight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ink: "Red pen"
        case .electric: "Electric"
        case .fire: "Fire"
        case .rainbow: "Rainbow"
        case .spotlight: "Spotlight"
        }
    }

    var lineWidth: CGFloat {
        switch self {
        case .ink: 4
        case .electric: 3
        case .fire: 7
        case .rainbow: 6
        case .spotlight: 2
        }
    }

    /// Spotlight strokes don't loop: once closed, they cut a hole in a dimmed screen (SpotlightLayer).
    var isSpotlight: Bool { self == .spotlight }

    /// What the stroke Canvas paints. Shader brushes only read its alpha.
    var inkColor: Color { self == .ink ? .red : .white }

    /// Room around the strokes for the stroke width plus how far the shader samples (its maxSampleOffset).
    func layerMargin(_ tuning: ShaderTuning.Values) -> CGSize {
        let reach: CGSize
        switch self {
        case .ink, .rainbow, .spotlight:
            reach = .zero
        case .electric:
            let radius = tuning.electricJitter / 2 + tuning.electricGlow + 1
            reach = CGSize(width: radius, height: radius)
        case .fire:
            reach = CGSize(width: tuning.fireWobble / 2 + 1, height: tuning.fireHeight + 1)
        }
        return CGSize(width: reach.width + lineWidth, height: reach.height + lineWidth)
    }

    /// Cursor and screen-frame tint.
    var accent: NSColor {
        switch self {
        case .ink: .systemRed
        case .electric: .systemCyan
        case .fire: .systemOrange
        case .rainbow: .systemPurple
        case .spotlight: .systemYellow
        }
    }

    var swatch: AnyShapeStyle {
        switch self {
        case .ink:
            AnyShapeStyle(Color.red)
        case .electric:
            AnyShapeStyle(LinearGradient(colors: [.white, .cyan, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
        case .fire:
            AnyShapeStyle(LinearGradient(colors: [.yellow, .orange, .red], startPoint: .top, endPoint: .bottom))
        case .rainbow:
            AnyShapeStyle(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
        case .spotlight:
            AnyShapeStyle(RadialGradient(colors: [.white, .white, Color(white: 0.25)], center: .center,
                                         startRadius: 0, endRadius: 11))
        }
    }

    /// Digit keys 1–5 pick brushes in palette order.
    init?(digit: String?) {
        guard let digit, let number = Int(digit), Brush.allCases.indices.contains(number - 1) else { return nil }
        self = Brush.allCases[number - 1]
    }
}

/// The palette's entrance: slides in from beyond the screen's right edge, a beat after the step before.
private struct SlideInFromRight: ViewModifier {
    let hasAppeared: Bool
    let step: Int

    func body(content: Content) -> some View {
        content
            .offset(x: hasAppeared ? 0 : BrushPalette.size.width + BrushPalette.edgeInset)
            .animation(.spring(response: 0.45, dampingFraction: 0.8).delay(Double(step) * 0.035), value: hasAppeared)
    }
}

/// The selected brush, whiteboard tool and color, shared by every screen's canvas.
/// Whether the whiteboard is up is remembered between launches; the tool isn't: the board opens
/// with the marker and the screen with the electric brush (see `selectDefaultTool`).
@MainActor
final class BrushState: ObservableObject {
    private static let whiteboardKey = "pen.whiteboard"

    /// Picking a brush switches from any whiteboard tool back to drawing with it.
    @Published var brush = Brush.electric {
        didSet {
            boardTool = nil
            isPointer = false
        }
    }

    @Published var showsWhiteboard: Bool {
        didSet {
            UserDefaults.standard.set(showsWhiteboard, forKey: Self.whiteboardKey)
            selectDefaultTool()
        }
    }

    /// nil draws with `brush`.
    @Published var boardTool: BoardTool? {
        didSet { if boardTool != nil { isPointer = false } }
    }
    /// No tool: clicking the active tool again turns drawing off, so the normal cursor works on the
    /// apps below while the ink stays up. Picking any tool turns drawing back on.
    @Published var isPointer = false
    @Published var boardColor = BoardColor.black

    init() {
        showsWhiteboard = UserDefaults.standard.bool(forKey: Self.whiteboardKey)
    }

    /// The whiteboard's marker while the board is up, the electric brush otherwise.
    /// Runs when the pen opens and whenever the board is shown or hidden.
    func selectDefaultTool() {
        if showsWhiteboard {
            boardTool = .marker
        } else {
            brush = .electric
        }
    }
}

extension View {
    /// Applies the brush's Metal shader (see PenShaders.metal) to a layer of its strokes.
    /// `origin` is the layer's screen position, so noise and color stay fixed to the screen as the layer grows.
    /// `tuning` supplies the Shader Lab parameters.
    @ViewBuilder
    func brushEffect(_ brush: Brush, time: Float, origin: CGPoint, tuning: ShaderTuning.Values) -> some View {
        let time = Shader.Argument.float(time)
        let origin = Shader.Argument.float2(origin)
        let margin = brush.layerMargin(tuning)
        let value: (Double) -> Shader.Argument = { .float(Float($0)) }
        switch brush {
        case .ink, .spotlight:
            self
        case .electric:
            layerEffect(ShaderLibrary.electric(time, origin, value(tuning.electricJitter), value(tuning.electricRate),
                                               value(tuning.electricGlow)),
                        maxSampleOffset: margin)
        case .fire:
            layerEffect(ShaderLibrary.fire(time, origin, value(tuning.fireHeight), value(tuning.fireSpeed),
                                           value(tuning.fireWobble)),
                        maxSampleOffset: margin)
        case .rainbow:
            colorEffect(ShaderLibrary.rainbow(time, origin, value(tuning.rainbowScale), value(tuning.rainbowSpeed)))
        }
    }
}

/// Vertical toolbar on the right edge: the brushes and "clear screen", then the whiteboard toggle.
struct BrushPalette: View {
    private enum Metrics {
        static let cell: CGFloat = 48
        static let swatch: CGFloat = 32
        static let spacing: CGFloat = 8
        static let padding: CGFloat = 10
        static let dividerHeight: CGFloat = 1
    }

    /// Brushes and "clear screen", a divider, then the whiteboard button.
    static var size: CGSize {
        let cells = CGFloat(Brush.allCases.count + 2)
        let height = Metrics.padding * 2 + cells * Metrics.cell + cells * Metrics.spacing + Metrics.dividerHeight
        return CGSize(width: Metrics.cell + Metrics.padding * 2, height: height)
    }

    /// How far outside the palette the screen's right edge is; the entrance starts beyond it.
    static let edgeInset: CGFloat = 32

    @ObservedObject var brushes: BrushState
    /// For "clear screen": enabled only while something is drawn on the screen.
    @ObservedObject var ink: InkModel

    /// False for the first frame; then the pill and its buttons slide in from the screen's edge.
    @State private var hasAppeared = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Self.size.width / 2, style: .continuous)
                .fill(.ultraThinMaterial)
                .modifier(SlideInFromRight(hasAppeared: hasAppeared, step: 0))
            buttons
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .environment(\.colorScheme, .dark)
        // The host view reaches to the screen's edge (PenCanvasView), so nothing is clipped on the way in.
        .frame(width: Self.size.width + Self.edgeInset, alignment: .leading)
        .onAppear { DispatchQueue.main.async { hasAppeared = true } }
    }

    private var buttons: some View {
        VStack(spacing: Metrics.spacing) {
            ForEach(Array(Brush.allCases.enumerated()), id: \.element) { index, brush in
                Button {
                    if isActive(brush) { brushes.isPointer = true } else { brushes.brush = brush }
                } label: {
                    Circle()
                        .fill(brush.swatch)
                        .frame(width: Metrics.swatch, height: Metrics.swatch)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white, lineWidth: isActive(brush) ? 2.5 : 0)
                                .padding(-6)
                        )
                        .frame(width: Metrics.cell, height: Metrics.cell)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("\(brush.title)  \(index + 1)")
                .modifier(SlideInFromRight(hasAppeared: hasAppeared, step: index + 1))
            }

            // One click clears everything drawn on the screen; the whiteboard is left alone
            // (it has its own "Clear board"). ⌘Z brings it back.
            Button { ink.clearScreen() } label: {
                Image(systemName: "eraser")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: Metrics.cell, height: Metrics.cell)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!ink.hasScreenItems)
            .opacity(ink.hasScreenItems ? 1 : 0.35)
            .help("Clear screen (⌘Z to undo)")
            .modifier(SlideInFromRight(hasAppeared: hasAppeared, step: Brush.allCases.count + 1))

            Rectangle()
                .fill(.white.opacity(0.2))
                .frame(width: Metrics.swatch, height: Metrics.dividerHeight)

            Button { brushes.showsWhiteboard.toggle() } label: {
                Image(systemName: brushes.showsWhiteboard ? "rectangle.inset.filled" : "rectangle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white.opacity(brushes.showsWhiteboard ? 1 : 0.7))
                    .frame(width: Metrics.cell, height: Metrics.cell)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.white.opacity(brushes.showsWhiteboard ? 0.18 : 0))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Whiteboard  W")
            .modifier(SlideInFromRight(hasAppeared: hasAppeared, step: Brush.allCases.count + 2))
        }
    }

    private func isActive(_ brush: Brush) -> Bool {
        !brushes.isPointer && brushes.boardTool == nil && brushes.brush == brush
    }
}
