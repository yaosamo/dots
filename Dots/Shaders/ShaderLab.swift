import AppKit
import SwiftUI

/// Floating window with a slider per shader parameter. It sits above the pen and Tasks overlays,
/// so changes show live while you draw or replay the frost.
@MainActor
final class ShaderLabController {
    private let onPreviewTasks: () -> Void
    private let onTogglePen: () -> Void
    private lazy var panel = makePanel()

    init(onPreviewTasks: @escaping () -> Void, onTogglePen: @escaping () -> Void) {
        self.onPreviewTasks = onPreviewTasks
        self.onTogglePen = onTogglePen
    }

    func show() {
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 680),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered, defer: false
        )
        panel.title = "Shader Lab"
        panel.level = DotsLevel.lab
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: ShaderLabView(
            tuning: .shared, onPreviewTasks: onPreviewTasks, onTogglePen: onTogglePen
        ))
        panel.center()
        return panel
    }
}

struct ShaderLabView: View {
    @ObservedObject var tuning: ShaderTuning
    let onPreviewTasks: () -> Void
    let onTogglePen: () -> Void

    @State private var didCopy = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Open/Close Tasks", action: onPreviewTasks)
                Button("Pen", action: onTogglePen)
                Spacer()
                Button("Reset") { tuning.reset() }
                Button(didCopy ? "Copied" : "Copy", action: copy)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            .padding(12)
            Divider()
            Form {
                ForEach(TuningSection.all) { section in
                    Section(section.title) {
                        ForEach(section.parameters) { parameter in
                            row(parameter)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 380, minHeight: 480)
    }

    private func row(_ parameter: TuningParameter) -> some View {
        let value = Binding(
            get: { tuning.values[keyPath: parameter.keyPath] },
            set: { tuning.values[keyPath: parameter.keyPath] = $0 }
        )
        return LabeledContent(parameter.title) {
            HStack {
                if let step = parameter.step {
                    Slider(value: value, in: parameter.range, step: step)
                } else {
                    Slider(value: value, in: parameter.range)
                }
                Text(ShaderTuning.format(value.wrappedValue) + parameter.unit)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
            }
            .frame(width: 220)
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(tuning.swiftLiteral, forType: .string)
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { didCopy = false }
    }
}
