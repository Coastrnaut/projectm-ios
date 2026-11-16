// AVCameraFrameProvider.swift — the rear or front camera through AVFoundation (CAM-001-R4, R6 to R9,
// R15; research CAM-001-D2, D4, D5; CAM-002 research D3-D5). iOS only.
//
// CAM-002: `position` chooses the wide-angle camera (`camera(for:)`). `select(_:)` on a running
// session swaps its input inside begin/commitConfiguration on the session queue (the session keeps
// running, no new prompt); the slot stays closed until the video queue has delivered every buffer
// queued before the swap, and each picture is stamped with its connection's source position, so the
// layer never draws the previous camera. A new RotationCoordinator follows the new device. Mirroring
// is not done here: the camera layer flips the picture (one place for every output).
//
// * `start()` (main thread, only from the user's choice of the camera visual): no back wide-angle
//   camera → `unavailable` without asking; access never decided → iOS's prompt (`requestingAccess`);
//   denied/restricted → those states; allowed → a session with that camera only (no microphone),
//   preset 1280×720 (or `.medium`), a BGRA video data output that discards late frames, delivered
//   on its own serial queue. `startRunning`/`stopRunning` run on a private serial session queue.
// * Each picture is wrapped by a `CVMetalTextureCache` as `.bgra8Unorm_srgb` (the GPU decodes it to
//   linear light) and replaces the newest-picture slot. CoreVideo owns those wrappers; nothing else
//   is allocated per picture. Nothing is written to storage, sent or analysed (CAM-001-R9).
// * The picture's rotation comes from `AVCaptureDevice.RotationCoordinator` (horizon-level capture
//   angle), observed on the main thread.
// * Interruption → `interrupted` and the picture is dropped; its end → `running`. A runtime error →
//   `failed`. CAM-013: each carries a `stopReason` mapped from the notification's reason key or
//   error code (research CAM-013-D1); an interruption keeps the session (the system resumes it,
//   D2), a runtime error releases it at once so iOS's indicator turns off and a Retry starts clean
//   (D4). `stop()` closes the slot at once (no picture is shown or kept from then on), stops
//   observing and sends `stopRunning` to the session queue immediately.
// CAM-003: `lens` chooses the back lens (wide, ultra wide, telephoto) from `lensInventory`;
// `selectLens(_:)` on a running back camera replaces the input with `CameraInputSwitch` on the
// session queue (one configuration; the previous input stays when the new one cannot be opened or
// added; else the wide lens; only with nothing addable `unavailable`). The lens actually in the
// session is read back on the session queue, so `lens` always names the running lens. A start whose
// lens cannot be opened falls back to the wide lens.
// CAM-004 (contracts/exposure-lock.md C3; research CAM-004-D2, D3): `setExposureLocked(_:)` runs
// `CameraExposureControl` on the session queue against the session's device and posts the state read
// back; every switch releases the previous device before its input is removed, and a stop or a
// runtime error releases it before `stopRunning`. While not running, `exposure` reports only whether
// the chosen camera can lock (read from the device, which starts nothing).
// CAM-005 (contracts/focus-point.md C3): `setFocusPoint(_:)` runs `CameraFocusControl` the same way,
// and every place that releases the exposure lock also resets the focus to continuous automatic focus
// at the centre (R8); `focus` is read back with the exposure.
// CAM-006 (contracts/white-balance-lock.md C3): `setWhiteBalanceLocked(_:)` runs `CameraWhiteBalanceControl`
// the same way; every place that releases the exposure lock also releases white balance (R8, R9), an
// interruption keeps it (R7), and `whiteBalance` is read back with the exposure.
// A generation number discards callbacks from an earlier start. Thread confinement: state,
// session reference, observers and generation on the main thread; the cache and the slot on the
// video queue (the slot is locked). Hence `@unchecked Sendable`.
#if canImport(AVFoundation) && canImport(Metal) && os(iOS) && !COMPOSITOR_NO_METAL
import AVFoundation
import CoreVideo
import Metal
import os

public final class AVCameraFrameProvider: NSObject, CameraFrameProvider, AVCaptureVideoDataOutputSampleBufferDelegate,
    @unchecked Sendable {
    private struct Unchecked<T>: @unchecked Sendable { let value: T }

    private let device: MTLDevice
    private let latest = LatestCameraFrame()
    private let sessionQueue = DispatchQueue(label: "org.projectmios.camera.session")
    private let videoQueue = DispatchQueue(label: "org.projectmios.camera.video")
    private var session: AVCaptureSession?
    private var cache: CVMetalTextureCache?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?
    private var observers: [NSObjectProtocol] = []
    private var generation: UInt64 = 0
    /// CAM-002: the chosen camera (main thread).
    public private(set) var position: CameraPosition = .back
    /// CAM-013: why the feed is interrupted or failed (main thread).
    public private(set) var stopReason: CameraStopReason?
    /// CAM-003: the back lenses this device has.
    public let lensInventory: any CameraLensInventory
    /// CAM-003: the back lens (main thread).
    public private(set) var lens: CameraLens = .wide
    public var availableLenses: [CameraLens] { lensInventory.backLenses }

    public private(set) var state: CameraFeedState = .idle {
        didSet {
            guard state != oldValue else { return }
            if state == .running { readExposure() } else { showChosenCameraCapability() }   // CAM-004
            onStateChange?(state)
        }
    }
    public var onStateChange: ((CameraFeedState) -> Void)?
    /// CAM-004: the current camera's exposure, read back (main thread).
    public private(set) var exposure: CameraExposureState = .notRunning(canLock: false) {
        didSet { if exposure != oldValue { onExposureChange?(exposure) } }
    }
    public var onExposureChange: ((CameraExposureState) -> Void)?
    /// CAM-005: the current camera's focus, read back (main thread).
    public private(set) var focus: CameraFocusState = .notRunning(canFocus: false) {
        didSet { if focus != oldValue { onFocusChange?(focus) } }
    }
    public var onFocusChange: ((CameraFocusState) -> Void)?
    /// CAM-006: the current camera's white balance, read back (main thread).
    public private(set) var whiteBalance: CameraWhiteBalanceState = .notRunning(canLock: false) {
        didSet { if whiteBalance != oldValue { onWhiteBalanceChange?(whiteBalance) } }
    }
    public var onWhiteBalanceChange: ((CameraWhiteBalanceState) -> Void)?
    /// CAM-008: set on the main thread, read on the video queue.
    private let masker = OSAllocatedUnfairLock<PersonMasker?>(initialState: nil)
    public var personMasker: PersonMasker? {
        get { masker.withLock { $0 } }
        set { masker.withLock { $0 = newValue } }
    }
    /// CAM-009: set on the main thread, read on the video queue.
    private let analyzer = OSAllocatedUnfairLock<(any CameraPictureAnalyzing)?>(initialState: nil)
    public var pictureAnalyzer: (any CameraPictureAnalyzing)? {
        get { analyzer.withLock { $0 } }
        set { analyzer.withLock { $0 = newValue } }
    }

    public init(device: MTLDevice, lensInventory: any CameraLensInventory = AVCameraLensInventory()) {
        self.device = device
        self.lensInventory = lensInventory
        super.init()
        showChosenCameraCapability()
    }

    /// CAM-003: the camera for the chosen position and, at the back, the chosen lens (else the wide lens).
    private func currentCamera() -> AVCaptureDevice? {
        guard position == .back else { return Self.camera(for: position) }
        return AVCameraLensInventory.backCamera(lens) ?? Self.camera(for: .back)
    }

    /// CAM-003: an input for the current camera; at the back, the wide lens when the chosen one cannot
    /// be opened (R7). `lens` follows the lens actually opened.
    private func makeCurrentInput() -> (AVCaptureDevice, AVCaptureDeviceInput)? {
        if let camera = currentCamera(), let input = try? AVCaptureDeviceInput(device: camera) {
            if position == .back { lens = AVCameraLensInventory.lens(of: camera.deviceType) ?? .wide }
            return (camera, input)
        }
        guard position == .back, lens != .wide, let wide = Self.camera(for: .back),
              let input = try? AVCaptureDeviceInput(device: wide) else { return nil }
        lens = .wide
        return (wide, input)
    }

    /// The back wide-angle camera, if this device has one.
    public static func backCamera() -> AVCaptureDevice? { camera(for: .back) }

    /// CAM-002: the wide-angle camera at a position, if this device has one.
    public static func camera(for position: CameraPosition) -> AVCaptureDevice? {
        let avPosition: AVCaptureDevice.Position = position == .front ? .front : .back
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: avPosition)
    }

    public func start() {
        guard session == nil, state != .requestingAccess, state != .starting else { return }
        generation &+= 1
        stopReason = nil
        let current = generation
        guard currentCamera() != nil else {   // checked first: no camera, no prompt (CAM-001-R6, CAM-002-R10)
            state = .unavailable
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            state = .requestingAccess
            AVCaptureDevice.requestAccess(for: .video) { [self] granted in
                DispatchQueue.main.async { [self] in
                    guard current == generation, state == .requestingAccess else { return }
                    if granted { configureAndRun() } else { state = .denied }
                }
            }
        case .restricted:
            state = .restricted
        case .denied:
            state = .denied
        @unknown default:
            state = .denied
        }
    }

    public func stop() {
        releaseSession()
        stopReason = nil
        state = .idle
    }

    /// CAM-013-D4: no more pictures, observers removed, the session stopped and released, the cache
    /// flushed. The state is left to the caller (`idle` for a stop, `failed` after a runtime error).
    private func releaseSession() {
        generation &+= 1
        latest.close()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        rotationObservation?.invalidate()
        rotationObservation = nil
        rotationCoordinator = nil
        if let session {
            let box = Unchecked(value: session)
            sessionQueue.async {
                Self.releaseExposure(in: box.value)   // CAM-004-R7: no lock outlives the session
                box.value.stopRunning()
            }
        }
        session = nil
        if let cache {
            let box = Unchecked(value: cache)
            videoQueue.async { CVMetalTextureCacheFlush(box.value, 0) }
        }
    }

    /// CAM-013-D1: the reason for an interruption (nil or unknown: `otherInterruption`).
    public static func stopReason(interruption: AVCaptureSession.InterruptionReason?) -> CameraStopReason {
        switch interruption {
        case .videoDeviceInUseByAnotherClient?, .audioDeviceInUseByAnotherClient?: return .anotherApp
        case .videoDeviceNotAvailableWithMultipleForegroundApps?: return .multitasking
        case .videoDeviceNotAvailableDueToSystemPressure?: return .systemPressure
        case .videoDeviceNotAvailableInBackground?: return .background
        default: return .otherInterruption
        }
    }

    /// CAM-013-D1: the reason for a runtime error.
    public static func stopReason(error: AVError.Code?) -> CameraStopReason {
        error == .mediaServicesWereReset ? .mediaServicesReset : .runtimeError
    }

    public func latestFrame() -> CameraFrame? { latest.read() }

    // MARK: - Camera choice (CAM-002-R7)

    public func select(_ position: CameraPosition) {
        guard position != self.position else { return }
        #if DEBUG
        let now = DispatchTime.now().uptimeNanoseconds
        debugCounters.withLockUnchecked { $0.switchStart = now; $0.target = position.rawValue; $0.switchMs = -1 }
        #endif
        self.position = position
        stopReason = nil   // CAM-013: a switch clears the reason
        latest.clear()
        latest.setPosition(position)
        switch state {
        case .idle, .denied, .restricted, .requestingAccess:
            showChosenCameraCapability()   // CAM-004: the chosen camera's capability
            return   // recorded; a pending prompt's answer configures the camera chosen last
        case .unavailable, .interrupted, .failed:
            stop()
            start()
        case .starting, .running:
            if session != nil, currentCamera() != nil {
                switchInput()
            } else {
                stop()
                start()   // no camera at the new position: `unavailable`, nothing asked
            }
        }
    }

    /// Replaces the running session's input with the chosen camera's (research CAM-002-D4).
    private func switchInput() {
        guard let session, let made = makeCurrentInput() else {
            stop()
            state = .unavailable
            return
        }
        let (camera, input) = made
        generation &+= 1
        let current = generation
        latest.close()   // no picture until the old camera's queued buffers are gone
        state = .starting
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        observe(session)   // the observers carry the generation
        followRotation(of: camera)
        let box = Unchecked(value: (session, input))
        let video = videoQueue
        sessionQueue.async { [self] in
            let (session, input) = box.value
            Self.releaseExposure(in: session)   // CAM-004-R6: before the input is removed
            session.beginConfiguration()
            let old = session.inputs
            old.forEach(session.removeInput)
            let added = session.canAddInput(input)
            if added { session.addInput(input) } else { old.forEach { if session.canAddInput($0) { session.addInput($0) } } }
            session.commitConfiguration()
            video.async { [self] in   // every buffer queued before the swap was refused by the closed slot
                DispatchQueue.main.async { [self] in
                    // An interruption during the swap moved `.starting` to `.interrupted`: still open the slot (its end
                    // then shows the new camera). Requiring `.starting` left the slot closed while the state later read
                    // running, so no picture ever showed after a switch (D2, D3: QA-011 B06, 2026-11-16).
                    guard current == generation, state == .starting || state == .interrupted else { return }
                    if added {
                        latest.open()
                        if state == .starting { state = .running }
                    } else {
                        stop()
                        state = .unavailable
                    }
                }
            }
        }
    }

    // MARK: - Lens choice (CAM-003-R6 to R9)

    public func selectLens(_ requested: CameraLens) {
        let target: CameraLens = lensInventory.resolve(requested)
        guard target != lens else { return }
        lens = target
        guard position == .back else { return }   // R9: recorded; the front camera keeps its wide lens
        switch state {
        case .idle, .denied, .restricted, .requestingAccess:
            showChosenCameraCapability()   // CAM-004
            return
        case .unavailable, .interrupted, .failed:
            stop()
            start()
        case .starting, .running:
            if session != nil { switchLens(to: target) } else { stop(); start() }
        }
    }

    /// Replaces the running session's lens through `CameraInputSwitch` on the session queue (contract C2).
    private func switchLens(to target: CameraLens) {
        guard let session else { return }
        generation &+= 1
        let current = generation
        latest.close()   // R8: no picture until the previous lens's queued buffers are gone
        state = .starting
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        observe(session)   // the observers carry the generation
        let box = Unchecked(value: session)
        let video = videoQueue
        sessionQueue.async { [self] in
            Self.releaseExposure(in: box.value)   // CAM-004-R6: before the input is removed
            let outcome: CameraInputSwitchOutcome = CameraInputSwitch.replace(
                in: box.value,
                makeInput: { () -> AVCaptureInput? in Self.makeBackInput(target) },
                makeFallback: { () -> AVCaptureInput? in Self.makeBackInput(.wide) })
            let running: CameraLens? = box.value.inputs.lazy.compactMap { (input: AVCaptureInput) -> CameraLens? in
                (input as? AVCaptureDeviceInput).flatMap { AVCameraLensInventory.lens(of: $0.device.deviceType) }
            }.first
            video.async { [self] in   // every buffer queued before the switch was refused by the closed slot
                DispatchQueue.main.async { [self] in
                    guard current == generation, state == .starting || state == .interrupted else { return }   // as switchInput
                    finishLensSwitch(outcome, running: running)
                }
            }
        }
    }

    private func finishLensSwitch(_ outcome: CameraInputSwitchOutcome, running: CameraLens?) {
        guard outcome != .noInput, let running, let camera = AVCameraLensInventory.backCamera(running) else {
            stop()
            state = .unavailable   // R7: nothing could be added
            return
        }
        lens = running   // keptPrevious: the previous lens; fellBackToWide: wide
        followRotation(of: camera)
        latest.setPosition(position)
        latest.open()
        if state == .starting { state = .running }   // an interruption keeps its state until it ends
    }

    /// An input for a back lens, or nil when that lens is missing or cannot be opened.
    private static func makeBackInput(_ lens: CameraLens) -> AVCaptureInput? {
        guard let camera = AVCameraLensInventory.backCamera(lens) else { return nil }
        return try? AVCaptureDeviceInput(device: camera)
    }

    /// Picture rotation from the device's RotationCoordinator (CAM-001; CAM-002-D5 for the front camera).
    private func followRotation(of camera: AVCaptureDevice) {
        rotationObservation?.invalidate()
        let coordinator = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: nil)
        rotationCoordinator = coordinator
        latest.setRotation(CameraRotation(degrees: Double(coordinator.videoRotationAngleForHorizonLevelCapture)))
        let slot = latest
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { coordinator, _ in
            slot.setRotation(CameraRotation(degrees: Double(coordinator.videoRotationAngleForHorizonLevelCapture)))
        }
    }

    // MARK: - Exposure (CAM-004)

    /// The device of the session's camera input (session queue).
    private static func exposureDevice(in session: AVCaptureSession) -> AVCaptureDevice? {
        session.inputs.lazy.compactMap { (input: AVCaptureInput) -> AVCaptureDevice? in (input as? AVCaptureDeviceInput)?.device }.first
    }

    /// Returns a locked device to continuous automatic exposure (session queue; R6, R7) and (CAM-005-R8)
    /// its focus to continuous automatic focus at the centre. Runs before every input removal and stop.
    private static func releaseExposure(in session: AVCaptureSession) {
        guard let camera = exposureDevice(in: session) else { return }
        CameraExposureControl.release(camera)
        CameraFocusControl.reset(camera)
        CameraWhiteBalanceControl.release(camera)   // CAM-006-R8, R9
    }

    /// While not running: only whether the chosen camera can lock exposure and focus on a point
    /// (reading device properties starts nothing).
    private func showChosenCameraCapability() {
        let camera: AVCaptureDevice? = currentCamera()
        exposure = .notRunning(canLock: camera?.supportsExposure(.locked) ?? false)
        focus = .notRunning(canFocus: camera.map { (device: AVCaptureDevice) -> Bool in CameraFocusControl.canFocus(device) } ?? false)
        whiteBalance = .notRunning(canLock: camera?.supportsWhiteBalance(.locked) ?? false)   // CAM-006
    }

    // MARK: - Focus (CAM-005)

    /// CAM-005-R1, R4, R5: focuses the running camera at `point` on the session queue; the state read
    /// back is posted. Unsupported or not running: nothing is configured.
    public func setFocusPoint(_ point: CameraFocusPoint) {
        guard state == .running, focus.canFocus, let session else { return }
        let box = Unchecked(value: session)
        readExposure { () -> Void in
            guard let camera = Self.exposureDevice(in: box.value) else { return }
            CameraFocusControl.focus(at: point, on: camera)
        }
    }

    /// CAM-006-R4: locks or releases the running camera's white balance on the session queue; the state
    /// read back is posted. Unsupported or not running: nothing is configured.
    public func setWhiteBalanceLocked(_ locked: Bool) {
        guard state == .running, whiteBalance.canLock, let session else { return }
        let box = Unchecked(value: session)
        readExposure { () -> Void in
            guard let camera = Self.exposureDevice(in: box.value) else { return }
            if locked { CameraWhiteBalanceControl.lock(camera) } else { CameraWhiteBalanceControl.release(camera) }
        }
    }

    public func setExposureLocked(_ locked: Bool) {
        guard state == .running, exposure.canLock, let session else { return }   // R3: nothing configured
        let box = Unchecked(value: session)
        readExposure { () -> Void in
            guard let camera = Self.exposureDevice(in: box.value) else { return }
            if locked { CameraExposureControl.lock(camera) } else { CameraExposureControl.release(camera) }
        }
    }

    /// Runs `change` on the session queue, then posts the device's state read back (R5). Discarded when
    /// the feed has moved on (another generation or no longer running).
    private func readExposure(_ change: @escaping @Sendable () -> Void = {}) {
        guard let session else { return }
        let current = generation
        let box = Unchecked(value: session)
        sessionQueue.async { [self] in
            change()
            let camera: AVCaptureDevice? = Self.exposureDevice(in: box.value)
            let read: CameraExposureState? = camera.map { (camera: AVCaptureDevice) -> CameraExposureState in
                CameraExposureControl.state(of: camera)
            }
            let readFocus: CameraFocusState? = camera.map { (camera: AVCaptureDevice) -> CameraFocusState in
                CameraFocusControl.state(of: camera)   // CAM-005-R12
            }
            let readWhiteBalance: CameraWhiteBalanceState? = camera.map { (camera: AVCaptureDevice) -> CameraWhiteBalanceState in
                CameraWhiteBalanceControl.state(of: camera)   // CAM-006-R6
            }
            DispatchQueue.main.async { [self] in
                guard current == generation, state == .running, let read, let readFocus, let readWhiteBalance else { return }
                exposure = read
                focus = readFocus
                whiteBalance = readWhiteBalance
            }
        }
    }

    // MARK: - Session

    private func configureAndRun() {
        state = .starting
        guard let made = makeCurrentInput() else {
            state = .unavailable
            return
        }
        let (camera, input) = made
        var newCache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &newCache) == kCVReturnSuccess, let newCache else {
            stopReason = .runtimeError
            state = .failed
            return
        }
        cache = newCache
        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = session.canSetSessionPreset(.hd1280x720) ? .hd1280x720 : .medium
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            state = .unavailable
            return
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        self.session = session

        followRotation(of: camera)
        latest.setPosition(position)
        observe(session)

        latest.open()
        let current = generation
        let box = Unchecked(value: session)
        sessionQueue.async { [self] in
            box.value.startRunning()
            let running = box.value.isRunning
            DispatchQueue.main.async { [self] in
                guard current == generation, state == .starting else { return }
                if !running { stopReason = .runtimeError }
                state = running ? .running : .failed
            }
        }
    }

    private func observe(_ session: AVCaptureSession) {
        let center = NotificationCenter.default
        let current = generation
        observers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main) {
            [self] (note: Notification) in
            guard current == generation, state == .running || state == .starting else { return }
            let raw: Int? = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)?.intValue
            let reason: AVCaptureSession.InterruptionReason? = raw.flatMap { (value: Int) -> AVCaptureSession.InterruptionReason? in
                AVCaptureSession.InterruptionReason(rawValue: value)
            }
            latest.clear()
            stopReason = Self.stopReason(interruption: reason)
            state = .interrupted
        })
        observers.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: .main) {
            [self] _ in
            guard current == generation, state == .interrupted else { return }
            stopReason = nil
            latest.open()   // never `.running` with a closed slot (a switch's completion may not have opened it yet)
            state = .running
        })
        observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) {
            [self] (note: Notification) in
            guard current == generation, state != .idle else { return }
            let code: AVError.Code? = (note.userInfo?[AVCaptureSessionErrorKey] as? AVError)?.code
            releaseSession()   // CAM-013-D4: the session stops after a runtime error; release it now
            stopReason = Self.stopReason(error: code)
            state = .failed
        })
    }

    // MARK: - Pictures (video queue)

    #if DEBUG
    /// QA-011: capture-path counters for the device test of a camera switch (calls, refused while closed, stored, the
    /// last stored position). Video queue writes, main thread reads.
    private let debugCounters = OSAllocatedUnfairLock(uncheckedState: (calls: 0, closed: 0, stored: 0, last: "none",
                                                                       switchStart: UInt64(0), target: "", switchMs: -1))
    public var debugCaptureSummary: String {
        let c = debugCounters.withLockUnchecked { $0 }
        return "state=\(state) open=\(latest.isOpen ? 1 : 0) pos=\(position.rawValue) calls=\(c.calls) closed=\(c.closed) "
            + "stored=\(c.stored) last=\(c.last) switchMs=\(c.switchMs)"
    }
    #endif

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        #if DEBUG
        let isOpen = latest.isOpen
        debugCounters.withLockUnchecked { $0.calls += 1; if !isOpen { $0.closed += 1 } }
        #endif
        guard latest.isOpen, let cache, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let width = CVPixelBufferGetWidth(pixels), height = CVPixelBufferGetHeight(pixels)
        var wrapper: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, pixels, nil, .bgra8Unorm_srgb, width, height, 0,
                                                        &wrapper) == kCVReturnSuccess,
              let wrapper, let texture = CVMetalTextureGetTexture(wrapper) else { return }
        let position: CameraPosition? = Self.position(of: connection)
        guard latest.store(texture, owner: CVMetalTextureHold(texture: wrapper, cache: cache), position: position) else { return }
        #if DEBUG
        let stamped = position?.rawValue ?? "nil", now = DispatchTime.now().uptimeNanoseconds
        debugCounters.withLockUnchecked {
            $0.stored += 1
            $0.last = stamped
            // CAM-002-S7: from select() to the first stored picture of the chosen camera.
            if $0.switchStart > 0, stamped == $0.target {
                $0.switchMs = Int((now - $0.switchStart) / 1_000_000)
                $0.switchStart = 0
            }
        }
        #endif
        let masker: PersonMasker? = personMasker
        let analyzer: (any CameraPictureAnalyzing)? = pictureAnalyzer
        guard masker != nil || analyzer != nil else { return }
        let stamp = latest.stamp
        // CAM-008-R4, CAM-009: each decides itself whether this picture is analysed
        masker?.offer(pixels, rotation: stamp.rotation, position: position ?? stamp.position)
        analyzer?.offer(pixels, rotation: stamp.rotation, position: position ?? stamp.position)
    }

    /// CAM-002-D3: the camera a buffer came from (nil: the slot's position).
    private static func position(of connection: AVCaptureConnection) -> CameraPosition? {
        switch connection.inputPorts.first?.sourceDevicePosition {
        case .front?: return .front
        case .back?: return .back
        default: return nil
        }
    }
}
#endif
