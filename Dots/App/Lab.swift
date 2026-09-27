#if DEBUG
import AppKit
import SwiftUI

// What Shader Lab and Welcome Lab share: debug-only windows with a slider per tuning value, which
// float above everything (the overlays and the welcome included) so changes show live.

/// One slider in a lab: a number in some tuning's values.
struct LabParameter<Values>: Identifiable {
    let title: String
    let keyPath: WritableKeyPath<Values, Double>
    let range: ClosedRange<Double>
    var step: Double?
    var unit = ""

    var id: String { title }
}

struct LabSection<Values>: Identifiable {
    let title: String
    let parameters: [LabParameter<Values>]

    var id: String { title }
}

enum LabPanel {
    /// A titled utility panel on every Space, above everything.
    @MainActor
    static func make(title: String, size: CGSize, content: some View) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered, defer: false
        )
        panel.title = title
        panel.level = DotsLevel.lab
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: content)
        return panel
    }
}

/// A parameter's slider, with its value (and unit) beside it.
struct LabSlider<Values>: View {
    let parameter: LabParameter<Values>
    @Binding var values: Values

    var body: some View {
        let value = Binding(
            get: { values[keyPath: parameter.keyPath] },
            set: { values[keyPath: parameter.keyPath] = $0 }
        )
        LabeledContent(parameter.title) {
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
}

/// Copies the tuning as a Swift literal (to paste as new defaults), then says "Copied" for a moment.
struct LabCopyButton: View {
    let literal: () -> String

    @State private var didCopy = false

    var body: some View {
        Button(didCopy ? "Copied" : "Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(literal(), forType: .string)
            didCopy = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { didCopy = false }
        }
        .keyboardShortcut("c", modifiers: [.command, .shift])
    }
}
#endif
