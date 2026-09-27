import AppKit
import SwiftUI

/// Floating window with a control for every welcome parameter. It sits above the welcome itself,
/// so layout changes show live; Replay restarts the welcome to see timing changes.
@MainActor
final class WelcomeLabController {
    private let onReplay: () -> Void
    private let onClose: () -> Void
    private lazy var panel = makePanel()

    init(onReplay: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.onReplay = onReplay
        self.onClose = onClose
    }

    func show() {
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 760),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered, defer: false
        )
        panel.title = "Welcome Lab"
        panel.level = DotsLevel.lab
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: WelcomeLabView(
            tuning: .shared, onReplay: onReplay, onClose: onClose
        ))
        // Top-right, clear of the dots and text in the middle.
        if let visible = NSScreen.primary?.visibleFrame {
            panel.setFrameTopLeftPoint(NSPoint(x: visible.maxX - panel.frame.width - 24, y: visible.maxY - 24))
        } else {
            panel.center()
        }
        return panel
    }
}

struct WelcomeLabView: View {
    @ObservedObject var tuning: WelcomeTuning
    let onReplay: () -> Void
    let onClose: () -> Void

    @State private var didCopy = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Replay", action: onReplay)
                    .keyboardShortcut("r", modifiers: [.command])
                Button("Close Welcome", action: onClose)
                Spacer()
                Button("Reset") { tuning.reset() }
                Button(didCopy ? "Copied" : "Copy", action: copy)
                    .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            .padding(12)
            Divider()
            Form {
                Section("Text") {
                    TextField("Message", text: $tuning.values.message, axis: .vertical)
                        .lineLimit(2...5)
                    TextField("Hint", text: $tuning.values.hint)
                }
                Section("Background") {
                    Picker("Background", selection: $tuning.background) {
                        ForEach(WelcomeTuning.Background.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Lightning style") {
                    Picker("Style", selection: $tuning.lightning) {
                        ForEach(WelcomeTuning.Lightning.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                ForEach(WelcomeSection.all) { section in
                    Section(section.title) {
                        ForEach(section.parameters) { parameter in
                            row(parameter)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
        .frame(minWidth: 400, minHeight: 520)
    }

    private func row(_ parameter: WelcomeParameter) -> some View {
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
