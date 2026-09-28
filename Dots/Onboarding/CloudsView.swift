import AppKit
import MetalKit
import SwiftUI

/// The welcome's clouds (Shaders/CloudShader.metal), drawn by Metal into a layer that's
/// `cloudResolution` of the screen's pixels and stretched up with smooth filtering, at up to
/// `cloudFPS`. The clouds are soft, so a small drawable barely shows and saves most of the work.
struct CloudsView: NSViewRepresentable {
    let startDate: Date
    let leftAt: Date?
    let seed: Float

    func makeNSView(context: Context) -> CloudsMetalView {
        CloudsMetalView(startDate: startDate, seed: seed)
    }

    func updateNSView(_ view: CloudsMetalView, context: Context) {
        view.leftAt = leftAt
    }
}

final class CloudsMetalView: MTKView, MTKViewDelegate {
    var leftAt: Date?

    private let startDate: Date
    private let seed: Float
    private let queue: MTLCommandQueue?
    private let pipeline: MTLRenderPipelineState?

    init(startDate: Date, seed: Float) {
        self.startDate = startDate
        self.seed = seed
        let device = MTLCreateSystemDefaultDevice()
        queue = device?.makeCommandQueue()
        pipeline = device.flatMap(Self.makePipeline)
        super.init(frame: .zero, device: device)
        delegate = self
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        framebufferOnly = true
        autoResizeDrawable = false
        layer?.isOpaque = false
        layer?.magnificationFilter = .linear
        layer?.contentsGravity = .resize
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static func makePipeline(device: MTLDevice) -> MTLRenderPipelineState? {
        guard let library = device.makeDefaultLibrary() else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "cloudVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "cloudFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        return try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    /// The clouds are only a backdrop: clicks go to the dots and buttons.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // MARK: Drawing

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let values = WelcomeTuning.values
        applyCost(values)
        guard let pipeline, let queue, bounds.width > 0,
              let pass = currentRenderPassDescriptor, let drawable = currentDrawable,
              let buffer = queue.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }

        let now = Date()
        let frame = CloudFrame(time: now.timeIntervalSince(startDate),
                               leaving: leftAt.map { now.timeIntervalSince($0) }, tuning: values)
        var uniforms = CloudUniforms(frame: frame, values: values, size: bounds.size, seed: seed)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<CloudUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        buffer.present(drawable)
        buffer.commit()
    }

    /// Resolution and frame rate from the tuning.
    private func applyCost(_ values: WelcomeTuning.Values) {
        let fps = Int(values.cloudFPS.rounded())
        if preferredFramesPerSecond != fps { preferredFramesPerSecond = fps }
        let backing = window?.backingScaleFactor ?? 2
        let scale = min(max(values.cloudResolution, 0.05), 1) * backing
        let size = CGSize(width: max(1, (bounds.width * scale).rounded()), height: max(1, (bounds.height * scale).rounded()))
        if drawableSize != size { drawableSize = size }
    }
}

/// Mirrors `CloudUniforms` in Shaders/CloudShader.metal: all floats, in the same order.
private struct CloudUniforms {
    var width, height, time, descend, leave, fade, seed: Float
    var scale, holes, softness, travel, reach, edgeFog, drift, veil: Float
    var layers, shapeOctaves, warpPasses, puffOctaves, shadeOctaves, wispOctaves, edgeOctaves: Float

    init(frame: CloudFrame, values: WelcomeTuning.Values, size: CGSize, seed: Float) {
        width = Float(size.width)
        height = Float(size.height)
        time = Float(frame.time)
        descend = Float(frame.descend)
        leave = Float(frame.leave)
        fade = Float(frame.fade)
        self.seed = seed
        scale = Float(values.cloudSize)
        holes = Float(values.cloudHoles)
        softness = Float(values.cloudSoftness)
        travel = Float(values.cloudDepth)
        reach = Float(values.cloudReach)
        edgeFog = Float(values.cloudEdgeFog)
        drift = Float(values.cloudDrift)
        veil = Float(values.cloudVeil)
        layers = Float(values.cloudLayers)
        shapeOctaves = Float(values.cloudShapeDetail)
        warpPasses = Float(values.cloudWarp)
        puffOctaves = Float(values.cloudPuffDetail)
        shadeOctaves = Float(values.cloudShadeDetail)
        wispOctaves = Float(values.cloudWispDetail)
        edgeOctaves = Float(values.cloudEdgeDetail)
    }
}
