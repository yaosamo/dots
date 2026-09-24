import AppKit
import SwiftUI

@MainActor
final class DotsBarController {
    private static let size = NSSize(width: 182, height: 38)
    private static let topInset: CGFloat = 6

    private let panel = FloatingPanel(level: DotsLevel.bar, keyable: false)
    private var screenObserver: NSObjectProtocol?

    init(coordinator: DotsCoordinator) {
        panel.collectionBehavior.insert(.stationary)
        panel.contentView = FirstClickHostingView(rootView: DotsBarView().environmentObject(coordinator))
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.position() }
        }
    }

    func show() {
        position()
        panel.orderFrontRegardless()
    }

    /// Centered at the top of the menu-bar screen, just under the menu bar (and notch).
    private func position() {
        guard let screen = NSScreen.primary else { return }
        let size = Self.size
        let origin = NSPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.visibleFrame.maxY - size.height - Self.topInset
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }
}

struct DotsBarView: View {
    @EnvironmentObject private var coordinator: DotsCoordinator

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Dot.allCases) { dot in
                DotButton(dot: dot, isActive: coordinator.active.contains(dot)) {
                    coordinator.toggle(dot)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
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
            ZStack {
                Circle()
                    .fill(isActive ? dot.tint : Color.white.opacity(0.9))
                    .frame(width: diameter, height: diameter)
                    // No bar behind the dots: a soft dark shadow keeps white dots visible on light screens.
                    .shadow(color: isActive ? dot.tint.opacity(0.9) : .black.opacity(0.35), radius: isActive ? 5 : 2)
                if isHovering {
                    Image(systemName: dot.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(isActive ? Color.white : Color.black.opacity(0.75))
                        .transition(.opacity)
                }
            }
            .frame(width: 26, height: 26)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(dot.isAvailable ? 1 : 0.35)
        .help(dot.isAvailable ? "\(dot.title)  \(dot.shortcutLabel)" : dot.title)
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { isHovering = hovering }
        }
    }

    private var diameter: CGFloat { isHovering ? 24 : 14 }
}
