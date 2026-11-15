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
// CAM-003: a lens inventory (`lensInventory`) and a `FakeCameraCaptureSession` whose input is set
// up on every start and replaced by `CameraInputSwitch` on a lens switch, exactly as the real
// provider does; lenses can fail at input creation (`failingLenses`) or be refused by the session.
// CAM-005: each stand-in camera also has a `FakeCameraFocusDevice` (`focusPointCameras` chooses which
// can focus on a point); `setFocusPoint` runs `CameraFocusControl` on the running input's device, and
// every place that releases the exposure lock also resets the focus (R8).
// CAM-006: each stand-in camera also has a `FakeCameraWhiteBalanceDevice` (`whiteBalanceLockCameras`
// chooses which can lock); `setWhiteBalanceLocked` runs `CameraWhiteBalanceControl` on the running input's
// device; every place that releases the exposure lock also releases white balance (R8, R9), and an
// interruption keeps it (R7).
// CAM-004: each stand-in camera has a `FakeCameraExposureDevice` (`exposureLockCameras` chooses which
// can lock); `setExposureLocked` runs `CameraExposureControl` on the running input's device, and the
// session's setup (every start and camera switch), a lens switch, `stop()` and `fail(_:)` release it
// first, exactly as the real provider does.
#if canImport(Metal) && !COMPOSITOR_NO_METAL
import CoreVideo
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
            if state == .running, let texture { deliver(texture) }
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
    /// CAM-003: the back lenses this stand-in device has.
    public let lensInventory: any CameraLensInventory
    /// CAM-003: the stand-in capture session (its input is the running lens; tests read it).
    public let session: FakeCameraCaptureSession
    /// CAM-003: the back lens (main thread).
    public private(set) var lens: CameraLens
    /// CAM-003: effective lens choices and the last switch's outcome (tests).
    public private(set) var lensSelectCount = 0
    public private(set) var lastLensOutcome: CameraInputSwitchOutcome?
    public var availableLenses: [CameraLens] { lensInventory.backLenses }

    public private(set) var state: CameraFeedState = .idle {
        didSet {
            guard state != oldValue else { return }
            refreshExposure()   // CAM-004
            onStateChange?(state)
        }
    }
    /// CAM-004: the current camera's exposure, read back from its fake device (main thread).
    public private(set) var exposure: CameraExposureState = .notRunning(canLock: false) {
        didSet { if exposure != oldValue { onExposureChange?(exposure) } }
    }
    public var onExposureChange: ((CameraExposureState) -> Void)?
    /// CAM-005: the current camera's focus, read back from its fake device (main thread).
    public private(set) var focus: CameraFocusState = .notRunning(canFocus: false) {
        didSet { if focus != oldValue { onFocusChange?(focus) } }
    }
    public var onFocusChange: ((CameraFocusState) -> Void)?
    /// CAM-006: the current camera's white balance, read back from its fake device (main thread).
    public private(set) var whiteBalance: CameraWhiteBalanceState = .notRunning(canLock: false) {
        didSet { if whiteBalance != oldValue { onWhiteBalanceChange?(whiteBalance) } }
    }
    public var onWhiteBalanceChange: ((CameraWhiteBalanceState) -> Void)?
    public var onStateChange: ((CameraFeedState) -> Void)?
    /// How many times `start()` asked for access (a real prompt is never shown).
    public private(set) var accessRequests = 0
    /// Starts and stops (tests).
    public private(set) var startCount = 0
    public private(set) var stopCount = 0

    public init(device: MTLDevice, scenario: CameraScenario, pattern: Pattern = .solid(Color(red: 188, green: 188, blue: 188)),
                width: Int = 64, height: Int = 48, rotation: CameraRotation = .none, position: CameraPosition = .back,
                availablePositions: Set<CameraPosition> = [.back, .front],
                lensInventory: (any CameraLensInventory)? = nil, failingLenses: Set<CameraLens> = [], lens: CameraLens = .wide,
                exposureLockCameras: Set<FakeCameraKey>? = nil, focusPointCameras: Set<FakeCameraKey>? = nil,
                whiteBalanceLockCameras: Set<FakeCameraKey>? = nil) {
        let inventory: any CameraLensInventory = lensInventory ?? FixedCameraLensInventory([.wide])
        self.lensInventory = inventory
        self.session = FakeCameraCaptureSession(failingLenses: failingLenses)
        session.exposureLockCameras = exposureLockCameras
        session.focusPointCameras = focusPointCameras   // CAM-005
        session.whiteBalanceLockCameras = whiteBalanceLockCameras   // CAM-006
        self.lens = inventory.resolve(lens)
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
        refreshExposure()
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
        releaseExposure()   // CAM-004-R7
        session.reset()   // CAM-003: a released session has no input
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
        refreshExposure()   // CAM-004: the new camera's state (or capability)
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
        deliver(texture)
    }

    /// A runtime error (CAM-013: of `reason`, an error kind). The slot closes, as a released session's would.
    public func fail(_ reason: CameraStopReason = .runtimeError) {
        guard state == .running || state == .starting || state == .interrupted, !reason.isInterruption else { return }
        latest.close()
        releaseExposure()   // CAM-004-R7
        session.reset()
        stopReason = reason
        state = .failed
    }

    /// CAM-013-R8: camera access turned off in Settings. iOS ends a running app when this happens,
    /// so the stand-in only makes every later start find access denied.
    public func withdrawAccess() {
        accessWithdrawn = true
    }

    // MARK: - Lenses (CAM-003)

    public func selectLens(_ requested: CameraLens) {
        let target: CameraLens = lensInventory.resolve(requested)
        guard target != lens else { return }
        lensSelectCount += 1
        let previous: CameraLens = lens
        lens = target
        defer { refreshExposure() }   // CAM-004: the new lens's state (or capability)
        guard position == .back else { return }   // R9: the front camera keeps its wide lens
        switch state {
        case .idle, .denied, .restricted, .requestingAccess:
            return
        case .unavailable, .interrupted, .failed:
            latest.close()
            startFeed()
        case .starting, .running:
            releaseExposure()   // CAM-004-R6: before the input is removed
            let fake: FakeCameraCaptureSession = session
            let outcome: CameraInputSwitchOutcome = CameraInputSwitch.replace(
                in: fake, makeInput: { () -> FakeCameraInput? in fake.makeInput(lens: target) },
                makeFallback: { () -> FakeCameraInput? in fake.makeInput(lens: .wide) })
            lastLensOutcome = outcome
            applyLensOutcome(outcome, previous: previous)
        }
    }

    private func applyLensOutcome(_ outcome: CameraInputSwitchOutcome, previous: CameraLens) {
        switch outcome {
        case .switched, .fellBackToWide:
            if outcome == .fellBackToWide { lens = .wide }
            latest.clear()   // R8: no picture of the previous lens; the new lens's first picture follows
            if state == .running, let texture { deliver(texture) }
        case .keptPrevious:
            lens = previous   // R6: the previous lens keeps running
        case .noInput:
            latest.close()
            session.stopRunning()
            state = .unavailable   // R7
        }
    }

    /// Sets up the session's single input for the current camera (empty session: the wanted lens,
    /// else the wide lens) and starts it. False when nothing could be added.
    private func configureSession() -> Bool {
        releaseExposure()   // CAM-004-R6: a camera switch or restart never keeps a lock
        session.reset()
        let fake: FakeCameraCaptureSession = session
        let wanted: CameraLens = position == .back ? lens : .wide
        let side: CameraPosition = position
        let outcome: CameraInputSwitchOutcome = CameraInputSwitch.replace(
            in: fake, makeInput: { () -> FakeCameraInput? in fake.makeInput(lens: wanted, position: side) },
            makeFallback: { () -> FakeCameraInput? in fake.makeInput(lens: .wide, position: side) })
        if outcome == .fellBackToWide, position == .back { lens = .wide }
        fake.startRunning()
        return outcome != .noInput
    }

    // MARK: - Exposure (CAM-004)

    /// The running input's device, if any.
    private var runningExposureDevice: FakeCameraExposureDevice? { session.configuredInputs.first?.device }

    /// Whether the chosen camera can lock (known without starting it).
    private var chosenCameraCanLock: Bool {
        guard scenario != .unavailable, availablePositions.contains(position) else { return false }
        return session.exposureDevice(lens: position == .back ? lens : .wide, position: position).supportsExposure(.locked)
    }

    public func setExposureLocked(_ locked: Bool) {
        guard state == .running, let device = runningExposureDevice, device.supportsExposure(.locked) else { return }   // R3
        if locked { CameraExposureControl.lock(device) } else { CameraExposureControl.release(device) }
        refreshExposure()   // R5: read back
    }

    /// Releases the lock and (CAM-005-R8) returns the focus to continuous automatic focus at the centre;
    /// called before every input removal and on every stop.
    private func releaseExposure() {
        if let device = runningExposureDevice { CameraExposureControl.release(device) }
        if let focusDevice = runningFocusDevice { CameraFocusControl.reset(focusDevice) }
        if let whiteBalanceDevice = runningWhiteBalanceDevice { CameraWhiteBalanceControl.release(whiteBalanceDevice) }   // CAM-006
    }

    /// Reads exposure and (CAM-005-R12) focus back from the running camera, or the chosen camera's capability.
    private func refreshExposure() {
        if state == .running, let device = runningExposureDevice {
            exposure = CameraExposureControl.state(of: device)
        } else {
            exposure = .notRunning(canLock: chosenCameraCanLock)
        }
        if state == .running, let focusDevice = runningFocusDevice {
            focus = CameraFocusControl.state(of: focusDevice)
        } else {
            focus = .notRunning(canFocus: chosenCameraCanFocus)
        }
        if state == .running, let whiteBalanceDevice = runningWhiteBalanceDevice {   // CAM-006-R6
            whiteBalance = CameraWhiteBalanceControl.state(of: whiteBalanceDevice)
        } else {
            whiteBalance = .notRunning(canLock: chosenCameraCanLockWhiteBalance)
        }
    }

    // MARK: - White balance (CAM-006)

    private var runningWhiteBalanceDevice: FakeCameraWhiteBalanceDevice? { session.configuredInputs.first?.whiteBalanceDevice }

    /// Whether the chosen camera can lock white balance (known without starting it).
    private var chosenCameraCanLockWhiteBalance: Bool {
        guard scenario != .unavailable, availablePositions.contains(position) else { return false }
        return session.whiteBalanceDevice(lens: position == .back ? lens : .wide, position: position).supportsWhiteBalance(.locked)
    }

    public func setWhiteBalanceLocked(_ locked: Bool) {
        guard state == .running, let device = runningWhiteBalanceDevice, device.supportsWhiteBalance(.locked) else { return }   // R3
        if locked { CameraWhiteBalanceControl.lock(device) } else { CameraWhiteBalanceControl.release(device) }
        refreshExposure()   // R6: read back
    }

    // MARK: - Focus (CAM-005)

    private var runningFocusDevice: FakeCameraFocusDevice? { session.configuredInputs.first?.focusDevice }

    /// Whether the chosen camera can focus on a point (known without starting it).
    private var chosenCameraCanFocus: Bool {
        guard scenario != .unavailable, availablePositions.contains(position) else { return false }
        return CameraFocusControl.canFocus(session.focusDevice(lens: position == .back ? lens : .wide, position: position))
    }

    public func setFocusPoint(_ point: CameraFocusPoint) {
        guard state == .running, let device = runningFocusDevice, CameraFocusControl.canFocus(device) else { return }   // R5
        CameraFocusControl.focus(at: point, on: device)
        refreshExposure()   // R12: read back
    }

    private func run() {
        state = .starting
        if texture == nil { texture = makeTexture() }
        guard let texture else {
            state = .failed
            return
        }
        guard configureSession() else {
            state = .unavailable
            return
        }
        latest.open()
        deliver(texture)
        stopReason = nil
        state = .running
    }

    /// CAM-008: the masker this stand-in offers its picture to (main thread).
    public var personMasker: PersonMasker?
    /// CAM-009: the analyzer this stand-in offers its picture to (main thread).
    public var pictureAnalyzer: (any CameraPictureAnalyzing)?
    /// CAM-008: the picture as a CoreVideo buffer for the masker, made once.
    private var pixelBuffer: CVPixelBuffer?

    /// Stores the picture and (CAM-008) offers it to the masker, as the real camera does per buffer.
    private func deliver(_ texture: MTLTexture) {
        guard latest.store(texture, position: position), personMasker != nil || pictureAnalyzer != nil else { return }
        if pixelBuffer == nil { pixelBuffer = makePixelBuffer() }
        guard let pixelBuffer else { return }
        personMasker?.offer(pixelBuffer, rotation: rotation, position: position)
        pictureAnalyzer?.offer(pixelBuffer, rotation: rotation, position: position)   // CAM-009
    }

    /// CAM-008 (tests): delivers the same picture again while running, as the next camera frame.
    public func deliverNextPicture() {
        if state == .running, let texture { deliver(texture) }
    }

    private func makePixelBuffer() -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let rowBytes: Int = CVPixelBufferGetBytesPerRow(buffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let c: Color = color(x: x, y: y)
                let i: Int = y * rowBytes + x * 4
                bytes[i] = c.blue; bytes[i + 1] = c.green; bytes[i + 2] = c.red; bytes[i + 3] = 255
            }
        }
        return buffer
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
