// StubCameraFrameProvider.swift — a deterministic stand-in camera (CAM-001-R13; research CAM-001-D7).
//
// No camera and no system permission: every `CameraScenario` is simulated synchronously on the
// caller's (main) thread, and the picture (solid, columns or rows of sRGB-encoded colors) is created
// once in `start()`. Tests, the iOS Simulator (which has no camera) and DEBUG UI tests
// (`-uitestCamera <scenario>`) use it; release builds use `AVCameraFrameProvider`.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import Metal

public final class StubCameraFrameProvider: CameraFrameProvider {
    /// Display-encoded (sRGB) 8-bit color, as a camera delivers it.
    public struct Color: Sendable, Equatable {
        public var red, green, blue: UInt8
        public init(red: UInt8, green: UInt8, blue: UInt8) { self.red = red; self.green = green; self.blue = blue }
    }

    public enum Pattern: Sendable, Equatable {
        case solid(Color)
        /// Equal vertical stripes, left to right.
        case columns([Color])
        /// Equal horizontal stripes, top to bottom.
        case rows([Color])
    }

    public let scenario: CameraScenario
    public let pattern: Pattern
    public let width: Int
    public let height: Int
    public var rotation: CameraRotation {
        didSet { latest.setRotation(rotation) }
    }
    private let device: MTLDevice
    private let latest = LatestCameraFrame()
    private var texture: MTLTexture?
    /// The scenario's answer once the (simulated) prompt was answered: later starts reuse it.
    private var decided: Bool?

    public private(set) var state: CameraFeedState = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    public var onStateChange: ((CameraFeedState) -> Void)?
    /// How many times `start()` asked for access (a real prompt is never shown).
    public private(set) var accessRequests = 0
    /// Starts and stops (tests).
    public private(set) var startCount = 0
    public private(set) var stopCount = 0

    public init(device: MTLDevice, scenario: CameraScenario, pattern: Pattern = .solid(Color(red: 188, green: 188, blue: 188)),
                width: Int = 64, height: Int = 48, rotation: CameraRotation = .none) {
        self.device = device
        self.scenario = scenario
        self.pattern = pattern
        self.width = max(width, 1)
        self.height = max(height, 1)
        self.rotation = rotation
        latest.setRotation(rotation)
    }

    /// True while the stand-in camera "runs" (it delivers pictures).
    public var isRunning: Bool { state == .running }

    public func start() {
        guard state != .running, state != .starting, state != .requestingAccess else { return }
        startCount += 1
        switch scenario {
        case .unavailable:
            state = .unavailable
        case .denied:
            state = .denied
        case .restricted:
            state = .restricted
        case .granted:
            run()
        case .notDeterminedGrant, .notDeterminedDeny:
            if decided == nil {
                accessRequests += 1
                state = .requestingAccess
                decided = scenario == .notDeterminedGrant
            }
            if decided == true { run() } else { state = .denied }
        }
    }

    public func stop() {
        guard state != .idle else { return }
        stopCount += 1
        latest.close()
        state = .idle
    }

    public func latestFrame() -> CameraFrame? { latest.read() }

    /// Another app or the system takes the camera.
    public func interrupt() {
        guard state == .running else { return }
        latest.clear()
        state = .interrupted
    }

    /// The camera is free again.
    public func endInterruption() {
        guard state == .interrupted, let texture else { return }
        state = .running
        latest.store(texture)
    }

    /// A runtime error.
    public func fail() {
        guard state == .running || state == .interrupted else { return }
        latest.clear()
        state = .failed
    }

    private func run() {
        state = .starting
        if texture == nil { texture = makeTexture() }
        guard let texture else {
            state = .failed
            return
        }
        latest.open()
        latest.store(texture)
        state = .running
    }

    private func makeTexture() -> MTLTexture? {
        let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm_srgb, width: width, height: height, mipmapped: false)
        d.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: d) else { return nil }
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let c = color(x: x, y: y)
                let i = (y * width + x) * 4
                bytes[i] = c.blue; bytes[i + 1] = c.green; bytes[i + 2] = c.red; bytes[i + 3] = 255
            }
        }
        bytes.withUnsafeBytes { raw in
            texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: raw.baseAddress!,
                            bytesPerRow: width * 4)
        }
        texture.label = "CAM-001 stub picture"
        return texture
    }

    private func color(x: Int, y: Int) -> Color {
        switch pattern {
        case let .solid(c): return c
        case let .columns(colors):
            guard !colors.isEmpty else { return Color(red: 0, green: 0, blue: 0) }
            return colors[min(x * colors.count / width, colors.count - 1)]
        case let .rows(colors):
            guard !colors.isEmpty else { return Color(red: 0, green: 0, blue: 0) }
            return colors[min(y * colors.count / height, colors.count - 1)]
        }
    }
}
#endif
