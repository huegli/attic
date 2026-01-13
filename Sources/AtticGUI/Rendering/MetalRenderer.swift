// =============================================================================
// MetalRenderer.swift - Metal-Based Emulator Display Renderer
// =============================================================================
//
// This file implements the Metal rendering pipeline for displaying the
// Atari 800 XL emulator output. Metal is Apple's low-level graphics API
// that provides direct access to the GPU for high-performance rendering.
//
// Why Metal?
// ----------
// - Low latency: Important for real-time emulation at 60fps
// - Efficient texture updates: We upload a new frame every 1/60th second
// - macOS native: Best integration with the system
//
// Rendering Pipeline:
// 1. CPU generates frame buffer (BGRA pixels) in EmulatorEngine
// 2. MetalRenderer uploads pixels to a Metal texture
// 3. A full-screen quad is rendered with the texture
// 4. The result is displayed in the MTKView
//
// The Atari 800 XL has a resolution of 384x240 pixels. This is scaled up
// to fit the window while maintaining the correct aspect ratio.
//
// =============================================================================

import MetalKit
import AtticCore

// =============================================================================
// MARK: - MetalRenderer
// =============================================================================

/// Metal-based renderer for the Atari display.
///
/// This class manages the Metal rendering pipeline for displaying emulator
/// output. It creates and maintains:
/// - Metal device and command queue
/// - Render pipeline state
/// - Screen texture (updated each frame)
/// - Vertex buffer for the display quad
///
/// Usage:
///
///     let renderer = try await MetalRenderer(metalView: mtkView)
///
///     // Each frame:
///     renderer.updateTexture(with: frameBuffer)
///     // MTKViewDelegate.draw() is called automatically
///
/// Note: This class is @MainActor because MTKView must be configured
/// on the main thread.
@MainActor
public class MetalRenderer: NSObject {
    // =========================================================================
    // MARK: - Properties
    // =========================================================================

    /// The Metal device (GPU).
    private let device: MTLDevice

    /// Command queue for submitting render commands.
    private let commandQueue: MTLCommandQueue

    /// The render pipeline state.
    private var pipelineState: MTLRenderPipelineState!

    /// Texture containing the Atari screen pixels.
    private var screenTexture: MTLTexture!

    /// Sampler state for texture sampling (nearest neighbor for crisp pixels).
    private var samplerState: MTLSamplerState!

    /// Vertex buffer for the full-screen quad.
    private var vertexBuffer: MTLBuffer!

    /// The MTKView we're rendering to.
    private weak var metalView: MTKView?

    /// Lock for thread-safe texture updates.
    private let textureLock = NSLock()

    /// Pending frame buffer to upload (set from emulation thread).
    /// Stored as Data to support both [UInt8] and Data input without extra copies.
    private var pendingFrameBuffer: Data?

    // =========================================================================
    // MARK: - Initialization
    // =========================================================================

    /// Creates a new MetalRenderer for the given view.
    ///
    /// - Parameter metalView: The MTKView to render to.
    /// - Throws: If Metal initialization fails.
    public init(metalView: MTKView) throws {
        // Get the default Metal device (GPU)
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MetalRendererError.noDevice
        }
        self.device = device

        // Create command queue for submitting GPU commands
        guard let commandQueue = device.makeCommandQueue() else {
            throw MetalRendererError.noCommandQueue
        }
        self.commandQueue = commandQueue

        self.metalView = metalView

        super.init()

        // Configure the MTKView
        metalView.device = device
        metalView.delegate = self
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.framebufferOnly = true
        metalView.preferredFramesPerSecond = 60
        metalView.isPaused = false
        metalView.enableSetNeedsDisplay = false

        // Set up rendering resources
        try setupPipeline()
        try setupTexture()
        setupSampler()
        setupVertexBuffer()
    }

    // =========================================================================
    // MARK: - Setup Methods
    // =========================================================================

    /// Sets up the render pipeline.
    ///
    /// The render pipeline defines how vertices and fragments (pixels) are
    /// processed. We use a simple pipeline with:
    /// - Vertex shader: Passes through vertex positions and texture coordinates
    /// - Fragment shader: Samples the screen texture
    private func setupPipeline() throws {
        // Load shader library from embedded source
        let shaderSource = Self.shaderSource
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: shaderSource, options: nil)
        } catch {
            throw MetalRendererError.shaderCompilationFailed(error.localizedDescription)
        }

        guard let vertexFunction = library.makeFunction(name: "vertexShader"),
              let fragmentFunction = library.makeFunction(name: "fragmentShader") else {
            throw MetalRendererError.shaderFunctionNotFound
        }

        // Create pipeline descriptor
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        // Create pipeline state
        pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }

    /// Creates the screen texture.
    ///
    /// The texture is 384x240 pixels in BGRA format, matching the Atari's
    /// resolution and our frame buffer format.
    private func setupTexture() throws {
        let textureDescriptor = MTLTextureDescriptor()
        textureDescriptor.pixelFormat = .bgra8Unorm
        textureDescriptor.width = AtariScreen.width
        textureDescriptor.height = AtariScreen.height
        textureDescriptor.usage = [.shaderRead]
        textureDescriptor.storageMode = .managed  // CPU-writable on macOS

        guard let texture = device.makeTexture(descriptor: textureDescriptor) else {
            throw MetalRendererError.textureCreationFailed
        }
        screenTexture = texture
    }

    /// Creates the texture sampler.
    ///
    /// We use nearest-neighbor filtering to preserve the crisp pixel look
    /// of the original Atari display.
    private func setupSampler() {
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .nearest  // No smoothing
        samplerDescriptor.magFilter = .nearest  // Crisp pixel scaling
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge

        samplerState = device.makeSamplerState(descriptor: samplerDescriptor)
    }

    /// Creates the vertex buffer for the full-screen quad.
    ///
    /// The quad covers the entire view with texture coordinates mapping
    /// the Atari screen texture.
    private func setupVertexBuffer() {
        // Vertex format: position (x, y), texCoord (u, v)
        // Two triangles forming a quad covering the screen
        let vertices: [Float] = [
            // Position      // TexCoord
            -1.0, -1.0,      0.0, 1.0,   // Bottom-left
             1.0, -1.0,      1.0, 1.0,   // Bottom-right
            -1.0,  1.0,      0.0, 0.0,   // Top-left

            -1.0,  1.0,      0.0, 0.0,   // Top-left
             1.0, -1.0,      1.0, 1.0,   // Bottom-right
             1.0,  1.0,      1.0, 0.0,   // Top-right
        ]

        vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Float>.size,
            options: .storageModeShared
        )
    }

    // =========================================================================
    // MARK: - Texture Update
    // =========================================================================

    /// Updates the screen texture with new frame data.
    ///
    /// This method is called from the emulation thread to provide new
    /// pixel data. The actual texture upload happens during the next draw.
    ///
    /// - Parameter pixels: BGRA pixel data (384 x 240 x 4 bytes).
    public func updateTexture(with pixels: [UInt8]) {
        guard pixels.count == AtariScreen.bgraBufferSize else {
            print("MetalRenderer: Invalid pixel buffer size: \(pixels.count)")
            return
        }

        // Convert [UInt8] to Data for storage
        let data = Data(pixels)

        textureLock.lock()
        pendingFrameBuffer = data
        textureLock.unlock()
    }

    /// Updates the screen texture with new frame data from Data.
    ///
    /// This is an optimized overload that accepts Data directly, avoiding
    /// an extra copy when frames come from network protocol buffers.
    ///
    /// - Parameter data: BGRA pixel data (384 x 240 x 4 bytes) as Data.
    public func updateTexture(with data: Data) {
        guard data.count == AtariScreen.bgraBufferSize else {
            print("MetalRenderer: Invalid pixel buffer size: \(data.count)")
            return
        }

        textureLock.lock()
        // Store Data directly - no copy needed!
        // Data is copy-on-write, so this just increments a reference count.
        pendingFrameBuffer = data
        textureLock.unlock()
    }

    /// Uploads pending frame data to the texture.
    ///
    /// Called at the start of each draw to upload any pending frame.
    private func uploadPendingFrame() {
        textureLock.lock()
        guard let frameData = pendingFrameBuffer else {
            textureLock.unlock()
            return
        }
        pendingFrameBuffer = nil
        textureLock.unlock()

        // Upload to texture
        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: AtariScreen.width, height: AtariScreen.height, depth: 1)
        )

        frameData.withUnsafeBytes { ptr in
            screenTexture.replace(
                region: region,
                mipmapLevel: 0,
                withBytes: ptr.baseAddress!,
                bytesPerRow: AtariScreen.width * 4
            )
        }
    }

    // =========================================================================
    // MARK: - Shader Source
    // =========================================================================

    /// Embedded Metal shader source code.
    ///
    /// We embed the shaders as a string to avoid needing a separate .metal file
    /// and the complexity of bundling resources with SPM.
    private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    // Vertex input structure
    struct VertexIn {
        float2 position [[attribute(0)]];
        float2 texCoord [[attribute(1)]];
    };

    // Vertex output / Fragment input structure
    struct VertexOut {
        float4 position [[position]];
        float2 texCoord;
    };

    // Vertex shader: Pass through position and texture coordinates
    vertex VertexOut vertexShader(uint vertexID [[vertex_id]],
                                   constant float4 *vertices [[buffer(0)]]) {
        VertexOut out;

        // Each vertex is 4 floats: x, y, u, v
        // Note: 'vertex' is a reserved keyword in Metal, so we use 'vtx'
        float4 vtx = vertices[vertexID];
        out.position = float4(vtx.xy, 0.0, 1.0);
        out.texCoord = vtx.zw;

        return out;
    }

    // Fragment shader: Sample the texture
    fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                    texture2d<float> screenTexture [[texture(0)]],
                                    sampler textureSampler [[sampler(0)]]) {
        return screenTexture.sample(textureSampler, in.texCoord);
    }
    """
}

// =============================================================================
// MARK: - MTKViewDelegate
// =============================================================================

extension MetalRenderer: MTKViewDelegate {
    /// Called when the view size changes.
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // We maintain aspect ratio in the view, so no special handling needed
    }

    /// Called to render a frame.
    ///
    /// This is called 60 times per second by the display link.
    public func draw(in view: MTKView) {
        // Upload any pending frame data
        uploadPendingFrame()

        // Get the current drawable and render pass descriptor
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            return
        }

        // Set clear color to black
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: 0, green: 0, blue: 0, alpha: 1
        )

        // Create command buffer
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        // Create render encoder
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: renderPassDescriptor
        ) else {
            return
        }

        // Set up rendering state
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setFragmentTexture(screenTexture, index: 0)
        renderEncoder.setFragmentSamplerState(samplerState, index: 0)

        // Draw the quad (6 vertices = 2 triangles)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)

        // End encoding
        renderEncoder.endEncoding()

        // Present and commit
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

// =============================================================================
// MARK: - Errors
// =============================================================================

/// Errors that can occur during Metal rendering setup.
public enum MetalRendererError: Error, LocalizedError {
    case noDevice
    case noCommandQueue
    case shaderCompilationFailed(String)
    case shaderFunctionNotFound
    case textureCreationFailed

    public var errorDescription: String? {
        switch self {
        case .noDevice:
            return "No Metal device available"
        case .noCommandQueue:
            return "Failed to create Metal command queue"
        case .shaderCompilationFailed(let message):
            return "Shader compilation failed: \(message)"
        case .shaderFunctionNotFound:
            return "Shader function not found in library"
        case .textureCreationFailed:
            return "Failed to create screen texture"
        }
    }
}
