#if DEBUG
import AppKit
import SwiftUI

/// Floating window with a control for every welcome parameter (debug builds). It sits above the
/// welcome itself, so layout changes show live; Replay restarts the welcome to see timing changes.
@MainActor
final class WelcomeLabController {
    private let onReplay: () -> Void
    private let onClose: () -> Void
    private var closeObserver: NSObjectProtocol?
    private lazy var panel: NSPanel = {
        let panel = LabPanel.make(title: "Welcome Lab", size: CGSize(width: 440, height: 760), content: WelcomeLabView(
            tuning: .shared, onReplay: onReplay, onClose: onClose
        ))
        // Top-right, clear of the dots and text in the middle.
        if let visible = NSScreen.primary?.visibleFrame {
            panel.setFrameTopLeftPoint(NSPoint(x: visible.maxX - panel.frame.width - 24, y: visible.maxY - 24))
        } else {
            panel.center()
        }
        // The clouds only measure what they cost while the readout is up.
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: panel, queue: .main
        ) { _ in
            MainActor.assumeIsolated { CloudStats.shared.isWatched = false }
        }
        return panel
    }()

    init(onReplay: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.onReplay = onReplay
        self.onClose = onClose
    }

    func show() {
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        CloudStats.shared.isWatched = true
    }
}

struct WelcomeLabView: View {
    @ObservedObject var tuning: WelcomeTuning
    let onReplay: () -> Void
    let onClose: () -> Void

    @ObservedObject private var stats = CloudStats.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Replay", action: onReplay)
                    .keyboardShortcut("r", modifiers: [.command])
                Button("Close Welcome", action: onClose)
                Spacer()
                Button("Reset") { tuning.reset() }
                LabCopyButton { tuning.swiftLiteral }
            }
            .padding(12)
            // What the clouds cost right now, to compare settings while they play.
            Text(String(format: "Clouds: %.0f fps · %.1f ms GPU a frame · %.0f × %.0f px",
                        stats.fps, stats.gpuMilliseconds, stats.drawnSize.width, stats.drawnSize.height))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
            Divider()
            Form {
                Section("Text") {
                    TextField("Message", text: $tuning.values.message, axis: .vertical)
                        .lineLimit(2...5)
                    TextField("Hint", text: $tuning.values.hint)
                }
                ForEach(WelcomeLabSections.all) { section in
                    Section(section.title) {
                        ForEach(section.parameters) { LabSlider(parameter: $0, values: $tuning.values) }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 400, minHeight: 520)
    }
}
#endif
