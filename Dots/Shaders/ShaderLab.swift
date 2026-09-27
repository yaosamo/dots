#if DEBUG
import AppKit
import SwiftUI

/// Floating window with a slider per shader parameter (debug builds). It sits above the pen and Tasks
/// overlays, so changes show live while you draw or replay the frost.
@MainActor
final class ShaderLabController {
    private let onPreviewTasks: () -> Void
    private let onTogglePen: () -> Void
    private lazy var panel: NSPanel = {
        let panel = LabPanel.make(title: "Shader Lab", size: CGSize(width: 420, height: 680), content: ShaderLabView(
            tuning: .shared, onPreviewTasks: onPreviewTasks, onTogglePen: onTogglePen
        ))
        panel.center()
        return panel
    }()

    init(onPreviewTasks: @escaping () -> Void, onTogglePen: @escaping () -> Void) {
        self.onPreviewTasks = onPreviewTasks
        self.onTogglePen = onTogglePen
    }

    func show() {
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }
}

struct ShaderLabView: View {
    @ObservedObject var tuning: ShaderTuning
    let onPreviewTasks: () -> Void
    let onTogglePen: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Open/Close Tasks", action: onPreviewTasks)
                Button("Pen", action: onTogglePen)
                Spacer()
                Button("Reset") { tuning.reset() }
                LabCopyButton { tuning.swiftLiteral }
            }
            .padding(12)
            Divider()
            Form {
                ForEach(ShaderLabSections.all) { section in
                    Section(section.title) {
                        ForEach(section.parameters) { LabSlider(parameter: $0, values: $tuning.values) }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 380, minHeight: 480)
    }
}
#endif
