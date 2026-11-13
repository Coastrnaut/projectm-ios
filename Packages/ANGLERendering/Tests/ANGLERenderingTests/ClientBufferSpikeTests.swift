// CMP-001-T02 (spike; ADR-0013, research CMP-001-D5): can the pinned ANGLE build draw into a
// texture that Metal samples? Queries the display's extension string at run time, then tries both
// documented client buffers: a Metal texture as an EGLImage (EGL_ANGLE_metal_texture_client_buffer)
// and an IOSurface as a pbuffer (EGL_ANGLE_iosurface_client_buffer). Each clears the GL bottom-left
// quadrant to half-transparent red and the rest to opaque blue, waits (glFinish), and reads the
// texture back through Metal, which also shows the row order Metal sees. Simulator results are not
// device evidence; the device check is CMP-001-T20 {device}.
import XCTest
import CANGLE
import IOSurface
import Metal

final class ClientBufferSpikeTests: XCTestCase {
    private static let side = 8

    private var display: EGLDisplay?
    private var config: EGLConfig?
    private var context: EGLContext?
    private var placeholder: EGLSurface?

    override func setUpWithError() throws {
        let platform: [EGLAttrib] = [EGLAttrib(EGL_PLATFORM_ANGLE_TYPE_ANGLE), EGLAttrib(EGL_PLATFORM_ANGLE_TYPE_METAL_ANGLE),
                                     EGLAttrib(EGL_NONE)]
        display = eglGetPlatformDisplay(EGLenum(EGL_PLATFORM_ANGLE_ANGLE), nil, platform)
        guard display != nil, eglInitialize(display, nil, nil) == EGL_TRUE else { throw XCTSkip("no ANGLE Metal display") }
        let attributes: [EGLint] = [EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
                                    EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT, EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
                                    EGL_BIND_TO_TEXTURE_RGBA, EGL_TRUE, EGL_NONE]
        var count: EGLint = 0
        XCTAssertEqual(eglChooseConfig(display, attributes, &config, 1, &count), EGLBoolean(EGL_TRUE))
        try XCTSkipIf(count == 0 || config == nil, "no pbuffer config")
        let contextAttributes: [EGLint] = [EGL_CONTEXT_MAJOR_VERSION, 3, EGL_CONTEXT_MINOR_VERSION, 0, EGL_NONE]
        context = eglCreateContext(display, config, nil, contextAttributes)
        let pbuffer: [EGLint] = [EGL_WIDTH, 1, EGL_HEIGHT, 1, EGL_NONE]
        placeholder = eglCreatePbufferSurface(display, config, pbuffer)
        XCTAssertNotNil(context)
        XCTAssertEqual(eglMakeCurrent(display, placeholder, placeholder, context), EGLBoolean(EGL_TRUE))
    }

    override func tearDown() {
        if display != nil {
            eglMakeCurrent(display, nil, nil, nil)
            if placeholder != nil { eglDestroySurface(display, placeholder) }
            if context != nil { eglDestroyContext(display, context) }
        }
    }

    private var extensions: [String] {
        guard let raw = eglQueryString(display, EGL_EXTENSIONS) else { return [] }
        return String(cString: raw).split(separator: " ").map(String.init)
    }

    /// Records the client-buffer extensions the pinned build reports (the spike's first question).
    func testReportsClientBufferExtensions() {
        let all = extensions
        let relevant = all.filter { $0.contains("iosurface") || $0.contains("metal") || $0.contains("image") || $0.contains("sync") }
        print("CMP-001 spike: EGL_VENDOR=\(eglQueryString(display, EGL_VENDOR).map { String(cString: $0) } ?? "?") "
              + "EGL_VERSION=\(eglQueryString(display, EGL_VERSION).map { String(cString: $0) } ?? "?")")
        print("CMP-001 spike: client-buffer extensions: \(relevant.joined(separator: " "))")
        var target: EGLint = 0
        eglGetConfigAttrib(display, config, EGL_BIND_TO_TEXTURE_TARGET_ANGLE, &target)
        print(String(format: "CMP-001 spike: EGL_BIND_TO_TEXTURE_TARGET_ANGLE=0x%X", target))
        XCTAssertFalse(all.isEmpty, "the display reports an extension string")
    }

    /// Reads a BGRA8 texture back as rows top-first (Metal's order).
    private func readBGRA(_ texture: MTLTexture) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: Self.side * Self.side * 4)
        texture.getBytes(&bytes, bytesPerRow: Self.side * 4, from: MTLRegionMake2D(0, 0, Self.side, Self.side), mipmapLevel: 0)
        return bytes
    }

    /// Pixel (x, y) in Metal's top-left coordinates as (r, g, b, a).
    private func pixel(_ bytes: [UInt8], _ x: Int, _ y: Int) -> [UInt8] {
        let i = (y * Self.side + x) * 4
        return [bytes[i + 2], bytes[i + 1], bytes[i], bytes[i + 3]]
    }

    /// Draws the pattern into `framebuffer`: whole picture opaque blue, GL bottom-left quadrant
    /// half-transparent red (premultiplied 0.5, 0, 0, 0.5).
    private func drawPattern(_ framebuffer: UInt32) {
        let s = Int32(Self.side)
        PMANGLEClearRect(framebuffer, 0, 0, s, s, 0, 0, 1, 1)
        PMANGLEClearRect(framebuffer, 0, 0, s / 2, s / 2, 0.5, 0, 0, 0.5)
        PMANGLEFinish()
    }

    /// Checks the pattern and reports which Metal row the GL bottom row lands in.
    private func assertPattern(_ bytes: [UInt8], label: String) {
        let topLeft = pixel(bytes, 0, 0), bottomLeft = pixel(bytes, 0, Self.side - 1), right = pixel(bytes, Self.side - 1, 0)
        print("CMP-001 spike \(label): Metal top-left \(topLeft), bottom-left \(bottomLeft), top-right \(right)")
        let red: [UInt8] = [128, 0, 0, 128], blue: [UInt8] = [0, 0, 255, 255]
        func near(_ a: [UInt8], _ b: [UInt8]) -> Bool { zip(a, b).allSatisfy { abs(Int($0) - Int($1)) <= 1 } }
        XCTAssertTrue(near(right, blue), "\(label): the right half is opaque blue")
        // GL's origin is bottom-left; whichever Metal row holds the red quadrant tells the flip.
        let flipped = near(bottomLeft, red) && near(topLeft, blue)
        let unflipped = near(topLeft, red) && near(bottomLeft, blue)
        XCTAssertTrue(flipped || unflipped, "\(label): the red quadrant is in one corner")
        print("CMP-001 spike \(label): GL row 0 is Metal row \(flipped ? "height-1 (y flipped)" : "0 (same order)")")
    }

    /// EGL_ANGLE_metal_texture_client_buffer: a Metal texture as an EGLImage, drawn through a GL
    /// framebuffer, read back by Metal.
    func testMetalTextureImageRoundTrip() throws {
        try XCTSkipUnless(extensions.contains("EGL_ANGLE_metal_texture_client_buffer"), "extension not reported")
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: Self.side, height: Self.side, mipmapped: false)
        d.usage = [.renderTarget, .shaderRead]
        d.storageMode = .shared
        let texture = try XCTUnwrap(device.makeTexture(descriptor: d))
        let image = eglCreateImage(display, nil, EGLenum(EGL_METAL_TEXTURE_ANGLE),
                                   Unmanaged.passUnretained(texture as AnyObject).toOpaque(), [EGLAttrib(EGL_NONE)])
        let imageError = eglGetError()
        print(String(format: "CMP-001 spike metal texture: eglCreateImage %@, eglGetError 0x%X", image == nil ? "failed" : "ok", imageError))
        let created = try XCTUnwrap(image, "eglCreateImage(EGL_METAL_TEXTURE_ANGLE) succeeds")
        defer { eglDestroyImage(display, created) }
        var glTexture: UInt32 = 0
        let framebuffer = PMANGLECreateImageFramebuffer(created, &glTexture)
        XCTAssertNotEqual(framebuffer, 0, "a GL framebuffer over the image is complete")
        defer { PMANGLEDeleteFramebuffer(framebuffer, glTexture) }
        drawPattern(framebuffer)
        assertPattern(readBGRA(texture), label: "metal texture")
    }

    /// EGL_ANGLE_metal_shared_event_sync: ANGLE signals an MTLSharedEvent after the GL work, so a
    /// Metal command buffer can wait for it on the GPU instead of glFinish on the CPU.
    func testSharedEventSync() throws {
        try XCTSkipUnless(extensions.contains("EGL_ANGLE_metal_shared_event_sync"), "extension not reported")
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let event = try XCTUnwrap(device.makeSharedEvent())
        let attributes: [EGLAttrib] = [EGLAttrib(EGL_SYNC_METAL_SHARED_EVENT_OBJECT_ANGLE),
                                       EGLAttrib(bitPattern: Unmanaged.passUnretained(event as AnyObject).toOpaque()),
                                       EGLAttrib(EGL_SYNC_METAL_SHARED_EVENT_SIGNAL_VALUE_LO_ANGLE), 7,
                                       EGLAttrib(EGL_SYNC_METAL_SHARED_EVENT_SIGNAL_VALUE_HI_ANGLE), 0,
                                       EGLAttrib(EGL_NONE)]
        let sync = eglCreateSync(display, EGLenum(EGL_SYNC_METAL_SHARED_EVENT_ANGLE), attributes)
        print(String(format: "CMP-001 spike shared event: eglCreateSync %@, eglGetError 0x%X", sync == nil ? "failed" : "ok", eglGetError()))
        let created = try XCTUnwrap(sync)
        defer { eglDestroySync(display, created) }
        PMANGLEFlush()
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let commands = try XCTUnwrap(queue.makeCommandBuffer())
        commands.encodeWaitForEvent(event, value: 7)
        commands.commit()
        commands.waitUntilCompleted()
        XCTAssertGreaterThanOrEqual(event.signaledValue, 7, "ANGLE signaled the event")
    }

    /// EGL_ANGLE_iosurface_client_buffer: an IOSurface as a pbuffer, drawn as the default
    /// framebuffer, read back through a Metal texture on the same IOSurface.
    func testIOSurfacePbufferRoundTrip() throws {
        try XCTSkipUnless(extensions.contains("EGL_ANGLE_iosurface_client_buffer"), "extension not reported")
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let surface = try XCTUnwrap(IOSurface(properties: [
            .width: Self.side, .height: Self.side, .bytesPerElement: 4, .bytesPerRow: Self.side * 4,
            .pixelFormat: 0x4247_5241,   // 'BGRA'
        ]))
        var target: EGLint = 0
        eglGetConfigAttrib(display, config, EGL_BIND_TO_TEXTURE_TARGET_ANGLE, &target)
        let attributes: [EGLint] = [EGL_WIDTH, EGLint(Self.side), EGL_HEIGHT, EGLint(Self.side), EGL_IOSURFACE_PLANE_ANGLE, 0,
                                    EGL_TEXTURE_TARGET, target, EGL_TEXTURE_INTERNAL_FORMAT_ANGLE, 0x80E1,   // GL_BGRA_EXT
                                    EGL_TEXTURE_FORMAT, EGL_TEXTURE_RGBA, EGL_TEXTURE_TYPE_ANGLE, 0x1401,     // GL_UNSIGNED_BYTE
                                    EGL_NONE]
        let pbuffer = eglCreatePbufferFromClientBuffer(display, EGLenum(EGL_IOSURFACE_ANGLE),
                                                       Unmanaged.passUnretained(surface).toOpaque(), config, attributes)
        print(String(format: "CMP-001 spike iosurface: pbuffer %@, eglGetError 0x%X", pbuffer == nil ? "failed" : "ok", eglGetError()))
        let created = try XCTUnwrap(pbuffer, "eglCreatePbufferFromClientBuffer(EGL_IOSURFACE_ANGLE) succeeds")
        defer {
            eglMakeCurrent(display, placeholder, placeholder, context)
            eglDestroySurface(display, created)
        }
        XCTAssertEqual(eglMakeCurrent(display, created, created, context), EGLBoolean(EGL_TRUE))
        drawPattern(0)
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: Self.side, height: Self.side, mipmapped: false)
        d.usage = [.shaderRead]
        d.storageMode = .shared
        let texture = try XCTUnwrap(device.makeTexture(descriptor: d, iosurface: unsafeBitCast(surface, to: IOSurfaceRef.self), plane: 0),
                                    "Metal wraps the IOSurface")
        assertPattern(readBGRA(texture), label: "iosurface")
    }
}
