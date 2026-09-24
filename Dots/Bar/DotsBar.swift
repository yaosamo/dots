import AppKit
import SwiftUI

/// Bar geometry, shared with the welcome screen so its dots land exactly on the bar's.
enum DotsBarMetrics {
    static let slot: CGFloat = 26
    static let spacing: CGFloat = 8
    static let horizontalPadding: CGFloat = 10
    static let height: CGFloat = 38
    static let topInset: CGFloat = 6
    static let dotDiameter: CGFloat = 14

    static func width(slots: Int) -> CGFloat {
        horizontalPadding * 2 + CGFloat(slots) * slot + CGFloat(max(slots - 1, 0)) * spacing
    }

    /// The bar's frame on `screen`: centered at the top, just under the menu bar (and notch).
    static func frame(slots: Int, on screen: NSScreen) -> NSRect {
        let size = NSSize(width: width(slots: slots), height: height)
        return NSRect(origin: NSPoint(x: screen.frame.midX - size.width / 2,
                                      y: screen.visibleFrame.maxY - size.height - topInset),
                      size: size)
    }

    /// Centers of the bar's slots, in top-left coordinates of a view covering `screen`.
    static func slotCenters(slots: Int, on screen: NSScreen) -> [CGPoint] {
        let bar = frame(slots: slots, on: screen)
        let y = screen.frame.maxY - bar.maxY + height / 2
        return (0..<slots).map { index in
            CGPoint(x: bar.minX - screen.frame.minX + horizontalPadding + slot / 2 + CGFloat(index) * (slot + spacing), y: y)
        }
    }
}

@MainActor
final class DotsBarController {
    private let panel = FloatingPanel(level: DotsLevel.bar, keyable: false)
    private let settings: DotSettings
    private var screenObserver: NSObjectProtocol?

    init(coordinator: DotsCoordinator) {
        settings = coordinator.settings
        panel.collectionBehavior.insert(.stationary)
        panel.contentView = FirstClickHostingView(
            rootView: DotsBarView().environmentObject(coordinator).environmentObject(coordinator.settings)
        )
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.position() }
        }
    }

    /// Also resizes the bar to the enabled dots, so call it after they change.
    func show() {
        position()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func position() {
        guard let screen = NSScreen.primary else { return }
        panel.setFrame(DotsBarMetrics.frame(slots: settings.barSlots, on: screen), display: true)
    }
}

struct DotsBarView: View {
    @EnvironmentObject private var coordinator: DotsCoordinator
    @EnvironmentObject private var settings: DotSettings

    var body: some View {
        GlassGroup {
            HStack(spacing: DotsBarMetrics.spacing) {
                ForEach(settings.enabled) { dot in
                    DotButton(dot: dot, isActive: coordinator.active.contains(dot)) {
                        coordinator.toggle(dot)
                    }
                }
                if settings.showsPlus {
                    PlusButton(action: coordinator.showSetup)
                }
            }
        }
        .padding(.horizontal, DotsBarMetrics.horizontalPadding)
        .contextMenu {
            Button("Quit Dots") { NSApp.terminate(nil) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .dark)
    }
}

private struct DotButton: View {
    let dot: Dot
    let isActive: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            // Plain dot at rest; on hover it grows and shows its icon.
            DotSurface(tint: isActive ? dot.tint : nil, diameter: diameter) {
                if isHovering {
                    Image(systemName: dot.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DotSurfaceStyle.glyphColor(isActive: isActive))
                        .transition(.opacity)
                }
            }
            .frame(width: DotsBarMetrics.slot, height: DotsBarMetrics.slot)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("\(dot.title)  \(dot.shortcutLabel)")
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { isHovering = hovering }
        }
    }

    private var diameter: CGFloat { isHovering ? 24 : DotsBarMetrics.dotDiameter }
}

/// The last slot while some tools are off: opens the dot setup.
private struct PlusButton: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            PlusDot(diameter: isHovering ? 24 : DotsBarMetrics.dotDiameter)
                .frame(width: DotsBarMetrics.slot, height: DotsBarMetrics.slot)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Add dots")
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { isHovering = hovering }
        }
    }
}

/// A ring with a plus: the + dot, in the bar and on the welcome screen.
struct PlusDot: View {
    let diameter: CGFloat

    var body: some View {
        if #available(macOS 26, *) {
            DotSurface(tint: nil, diameter: diameter) {
                plus.foregroundStyle(DotSurfaceStyle.glyphColor(isActive: false))
            }
        } else {
            Circle()
                .strokeBorder(Color.white.opacity(0.9), lineWidth: 1.5)
                .frame(width: diameter, height: diameter)
                .overlay(plus.foregroundStyle(Color.white.opacity(0.9)))
                .shadow(color: .black.opacity(0.35), radius: 2)
        }
    }

    private var plus: some View {
        Image(systemName: "plus").font(.system(size: diameter * 0.5, weight: .bold))
    }
}

/// A dot's body. On macOS 26+ it's Liquid Glass, so the dots pick up whatever is behind them:
/// a pearly white bead while the tool is off, glass tinted with the tool's color while it's on.
/// Earlier systems get the flat white and colored dots.
///
/// Tried side by side over dark wallpaper and white windows (the app is never frontmost, which
/// matters): `.regular` tints wash out to grey in inactive windows, so both states use `.clear`.
/// Plain `.clear` vanishes on white, hence the white tint plus a hairline ring; shadows smudged.
///
/// `content` (the icon) is the glass's own content: glass draws it on top of itself, whereas a
/// sibling view layered above would end up under the glass inside a GlassEffectContainer.
struct DotSurface<Content: View>: View {
    /// nil while the tool is off.
    let tint: Color?
    let diameter: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 26, *) {
            // Color.clear keeps the glass drawn when there's no icon (content can be empty).
            ZStack { Color.clear; content }
                .frame(width: diameter, height: diameter)
                .glassEffect(.clear.tint(tint?.opacity(0.85) ?? .white.opacity(0.6)), in: Circle())
                .overlay {
                    if tint == nil { Circle().strokeBorder(Color.black.opacity(0.14), lineWidth: 0.5) }
                }
        } else {
            Circle()
                .fill(tint ?? Color.white.opacity(0.9))
                .frame(width: diameter, height: diameter)
                // No bar behind the dots: a soft dark shadow keeps white dots visible on light screens.
                .shadow(color: tint?.opacity(0.9) ?? .black.opacity(0.35), radius: tint == nil ? 2 : 5)
                .overlay(content)
        }
    }
}

enum DotSurfaceStyle {
    /// Icons: white on colored dots, dark on the pale ones.
    static func glyphColor(isActive: Bool) -> Color {
        isActive ? .white : .black.opacity(0.7)
    }
}

/// Lets neighbouring glass dots blend into each other as they grow on hover (macOS 26+).
private struct GlassGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: DotsBarMetrics.spacing) { content }
        } else {
            content
        }
    }
}
