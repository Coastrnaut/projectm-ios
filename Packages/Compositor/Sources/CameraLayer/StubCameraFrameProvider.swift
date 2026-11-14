// StubCameraFrameProvider.swift — a deterministic stand-in camera (CAM-001-R13; research CAM-001-D7).
//
// No camera and no system permission: every `CameraScenario` is simulated synchronously on the
// caller's (main) thread, and the picture (solid, columns or rows of sRGB-encoded colors) is created
// once in `start()`. Tests, the iOS Simulator (which has no camera) and DEBUG UI tests
// (`-uitestCamera <scenario>`) use it; release builds use `AVCameraFrameProvider`.
// CAM-002: both positions (`select`), a missing front camera (`availablePositions`) and an asymmetric
// `.marker` picture, so the mirror and the camera switch are testable without a camera.
// CAM-013: `interrupt(_:)`, `endInterruption()`, `fail(_:)` and `withdrawAccess()` inject every
// interruption reason, its end, both runtime error kinds and a revoked permission (seen, as on iOS,
// at the next start); `stopReason` is set before the state callback.
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
        /// CAM-002: `marker` in the top-left quarter (x < width/2, y < height/2), `background` elsewhere.
        case marker(background: Color, marker: Color)
    }

    public let scenario: CameraScenario
    public let pattern: Pattern
    public let width: Int
    public let height: Int
    /// CAM-007: a change while running delivers the next picture with the new turn at once, as a real
    /// camera's next frame would after the device turns.
    public var rotation: CameraRotation {
        didSet {
            latest.setRotation(rotation)
            if state == .running, let texture { latest.store(texture, position: position) }
        }
    }
    /// CAM-002: the cameras this stand-in device has (`scenario` `.unavailable` means none at all).
    public let availablePositions: Set<CameraPosition>
    /// CAM-002: the chosen camera (main thread).
    public private(set) var position: CameraPosition
    /// CAM-002: effective camera switches (tests).
    public private(set) var selectCount = 0
    private let device: MTLDevice
    private let latest = LatestCameraFrame()
    private var texture: MTLTexture?
    /// The scenario's answer once the (simulated) prompt was answered: later starts reuse it.
    private var decided: Bool?
    /// CAM-013: access was withdrawn (in Settings); every later start finds it denied.
    public private(set) var accessWithdrawn = false
    /// CAM-013: why the feed is interrupted or failed (contracts/camera-recovery.md C1).
    public private(set) var stopReason: CameraStopReason?

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
                width: Int = 64, height: Int = 48, rotation: CameraRotation = .none, position: CameraPosition = .back,
                availablePositions: Set<CameraPosition> = [.back, .front]) {
        self.device = device
        self.position = position
        self.availablePositions = availablePositions
        self.scenario = scenario
        self.pattern = pattern
        self.width = max(width, 1)
        self.height = max(height, 1)
        self.rotation = rotation
        latest.setRotation(rotation)
        latest.setPosition(position)
    }

    /// True while the stand-in camera "runs" (it delivers pictures).
    public var isRunning: Bool { state == .running }

    public func start() {
        guard state != .running, state != .starting, state != .requestingAccess else { return }
        startCount += 1
        startFeed()
    }

    /// The scenario's answer for the current position (also a camera switch, without passing through idle).
    private func startFeed() {
        stopReason = nil
        if accessWithdrawn, scenario != .unavailable, availablePositions.contains(position) {   // CAM-013-R8
            state = .denied
            return
        }
        switch scenario {
        case .unavailable:
            state = .unavailable
        case _ where !availablePositions.contains(position):   // CAM-002-R10: no camera here, nothing asked
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
        stopReason = nil
        state = .idle
    }

    public func latestFrame() -> CameraFrame? { latest.read() }

    /// CAM-002: chooses the camera. The held picture is dropped first, so no picture of the previous
    /// camera is returned afterwards; a running or broken feed starts again with the new camera.
    public func select(_ position: CameraPosition) {
        guard position != self.position else { return }
        selectCount += 1
        stopReason = nil   // CAM-013: a switch clears the reason
        latest.clear()
        self.position = position
        latest.setPosition(position)
        switch state {
        case .idle, .denied, .restricted, .requestingAccess:
            break
        case .starting, .running, .unavailable, .interrupted, .failed:
            latest.close()
            startFeed()   // straight to the new camera: the badge never sees idle (CAM-002-R7, R8)
        }
    }

    /// Another app or the system takes the camera (CAM-013: for `reason`, an interruption kind).
    public func interrupt(_ reason: CameraStopReason = .otherInterruption) {
        guard state == .running || state == .starting, reason.isInterruption else { return }
        latest.clear()
        stopReason = reason
        state = .interrupted
    }

    /// The camera is free again.
    public func endInterruption() {
        guard state == .interrupted, let texture else { return }
        stopReason = nil
        state = .running
        latest.store(texture, position: position)
    }

    /// A runtime error (CAM-013: of `reason`, an error kind). The slot closes, as a released session's would.
    public func fail(_ reason: CameraStopReason = .runtimeError) {
        guard state == .running || state == .starting || state == .interrupted, !reason.isInterruption else { return }
        latest.close()
        stopReason = reason
        state = .failed
    }

    /// CAM-013-R8: camera access turned off in Settings. iOS ends a running app when this happens,
    /// so the stand-in only makes every later start find access denied.
    public func withdrawAccess() {
        accessWithdrawn = true
    }

    private func run() {
        state = .starting
        if texture == nil { texture = makeTexture() }
        guard let texture else {
            state = .failed
            return
        }
        latest.open()
        latest.store(texture, position: position)
        stopReason = nil
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
        case let .marker(background, marker):
            let inMarker: Bool = x < width / 2 && y < height / 2
            return inMarker ? marker : background
        }
    }
}
#endif
