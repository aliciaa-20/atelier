import AppKit
import CoreVideo
import MetalKit
import MetalPerformanceShaders

struct BendParameters {
    var progress: Float = 0
    var perspective: Float = 1
    var blur: Float = 0.9
    var shadow: Float = 0.35
    var style: Float = 0
}

private enum RenderError: LocalizedError {
    case allocation(String)
    case encoding

    var errorDescription: String? {
        switch self {
        case .allocation(let resource): return "Could not allocate \(resource) for rendering."
        case .encoding: return "Could not create the render encoder."
        }
    }
}

/// Adapted from IuCC123/BendMac's `Renderer.swift` (MIT). First `MTKView`/
/// Metal pipeline in Atelier -- establishes the pattern for anything that
/// comes after it.
final class BendRenderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private var cache: CVMetalTextureCache!
    private let fallback: MTLTexture
    private var blurTextures = [MTLTexture]()
    private var blurKernels = [MPSImageGaussianBlur]()
    private var blurStrength: Float = -1
    private lazy var scaleKernel = MPSImageBilinearScale(device: device)
    private var blurredSource: MTLTexture?
    let frames: FrameStore
    var parameters: @MainActor () -> BendParameters = { BendParameters() }

    init(frames: FrameStore, preview: CGImage? = nil) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
            let library = device.makeDefaultLibrary()
        else { throw NSError(domain: "Metal unavailable", code: 1) }
        self.device = device
        self.queue = queue
        self.frames = frames
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "bendVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "bendFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let cg = preview ?? Self.fallbackImage()
        let td = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: cg.width, height: cg.height, mipmapped: false)
        guard let texture = device.makeTexture(descriptor: td) else {
            throw RenderError.allocation("the fallback texture")
        }
        var pixels = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            let context = CGContext(
                data: bytes.baseAddress, width: cg.width, height: cg.height, bitsPerComponent: 8,
                bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            texture.replace(
                region: MTLRegionMake2D(0, 0, cg.width, cg.height), mipmapLevel: 0,
                withBytes: bytes.baseAddress!, bytesPerRow: cg.width * 4)
        }
        fallback = texture
        super.init()
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
    }
    func makeView() -> MTKView {
        let view = MTKView(frame: .zero, device: device)
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.preferredFramesPerSecond = 60
        view.framebufferOnly = true
        view.delegate = self
        return view
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable, let pass = view.currentRenderPassDescriptor,
            let command = queue.makeCommandBuffer()
        else { return }
        var retained: CVMetalTexture?
        var texture = fallback
        let sourceFrame = frames.get()
        if let frame = sourceFrame {
            CVMetalTextureCacheCreateTextureFromImage(
                nil, cache, frame, nil, .bgra8Unorm, CVPixelBufferGetWidth(frame),
                CVPixelBufferGetHeight(frame), 0, &retained)
            if let retained, let live = CVMetalTextureGetTexture(retained) { texture = live }
        }
        var p = MainActor.assumeIsolated { parameters() }
        // The live effect can omit blur under memory pressure; that's an
        // acceptable degrade -- the fold shape itself must never fail to draw.
        let unblurred = [texture, texture, texture, texture]
        let blurred =
            p.progress < 0.0001
            ? unblurred
            : (try? encodeBlur(texture, command: command, strength: p.blur)) ?? unblurred
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            blurredSource = nil
            return
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        for (i, t) in blurred.enumerated() { encoder.setFragmentTexture(t, index: i + 1) }
        encoder.setFragmentBytes(&p, length: MemoryLayout<BendParameters>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        command.present(drawable)
        // Retain the CV-backed texture until GPU completion.
        let held = (retained, sourceFrame)
        command.addCompletedHandler { _ in withExtendedLifetime(held) {} }
        command.commit()
    }
    private func encodeBlur(_ source: MTLTexture, command: MTLCommandBuffer, strength: Float) throws
        -> [MTLTexture]
    {
        if strength < 0.001 { return [source, source, source, source] }
        // Cap the blur working resolution independently of the Retina capture.
        // Sigma scales with this width to preserve the intended blur radius.
        let w = max(1, min(source.width / 4, 480))
        let h = max(1, source.height * w / source.width)
        if blurTextures.count != 5 || blurTextures.first?.width != w || blurTextures.first?.height != h {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
            descriptor.usage = [.shaderRead, .shaderWrite]
            descriptor.storageMode = .private
            blurTextures = (0..<5).compactMap { _ in device.makeTexture(descriptor: descriptor) }
            blurStrength = -1
            blurredSource = nil
        }
        guard blurTextures.count == 5 else { throw RenderError.allocation("blur textures") }
        if abs(blurStrength - strength) > 0.001 {
            blurredSource = nil
            blurKernels = [4.0, 10.0, 28.0, 64.0].map {
                let kernel = MPSImageGaussianBlur(
                    device: device, sigma: Float($0) * Float(w) / 880 * strength / 0.9)
                kernel.edgeMode = .clamp
                return kernel
            }
            blurStrength = strength
        }
        // The static fallback wallpaper needs new blur passes only when strength changes.
        if source === fallback && blurredSource === fallback && abs(blurStrength - strength) <= 0.001 {
            return Array(blurTextures.dropFirst())
        }
        scaleKernel.encode(
            commandBuffer: command, sourceTexture: source, destinationTexture: blurTextures[0])
        for i in 0..<4 {
            blurKernels[i].encode(
                commandBuffer: command, sourceTexture: blurTextures[0],
                destinationTexture: blurTextures[i + 1])
        }
        blurredSource = source
        return Array(blurTextures.dropFirst())
    }
    /// Shown until the first real capture frame arrives, and behind the
    /// live preview in Settings before a real desktop frame is available.
    static func fallbackImage() -> CGImage {
        let size = NSSize(width: 1280, height: 800)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGradient(colors: [
                NSColor(red: 0.16, green: 0.23, blue: 0.34, alpha: 1),
                NSColor(red: 0.57, green: 0.65, blue: 0.75, alpha: 1),
            ])!.draw(in: rect, angle: 90)
            for layer in stride(from: 4, through: 0, by: -1) {
                let path = NSBezierPath()
                path.move(to: .zero)
                for i in 0...100 {
                    let x = Double(i) / 100 * 1280
                    let y =
                        130 + Double(layer) * 65 + sin(x / 210 + Double(layer) * 1.1) * 45 + sin(
                            x / 95 + Double(layer)) * 15
                    path.line(to: NSPoint(x: x, y: y))
                }
                path.line(to: NSPoint(x: 1280, y: 0))
                path.close()
                NSColor(
                    calibratedRed: 0.15 + Double(layer) * 0.09, green: 0.2 + Double(layer) * 0.09,
                    blue: 0.28 + Double(layer) * 0.09, alpha: 1
                ).setFill()
                path.fill()
            }
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }
}
