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
// A generation number discards callbacks from an earlier start. Thread confinement: state,
// session reference, observers and generation on the main thread; the cache and the slot on the
// video queue (the slot is locked). Hence `@unchecked Sendable`.
#if canImport(AVFoundation) && canImport(Metal) && os(iOS) && !COMPOSITOR_NO_METAL
import AVFoundation
import CoreVideo
import Metal

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

    public private(set) var state: CameraFeedState = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    public var onStateChange: ((CameraFeedState) -> Void)?

    public init(device: MTLDevice) {
        self.device = device
        super.init()
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
        guard Self.camera(for: position) != nil else {   // checked first: no camera, no prompt (CAM-001-R6, CAM-002-R10)
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
            sessionQueue.async { box.value.stopRunning() }
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
        self.position = position
        stopReason = nil   // CAM-013: a switch clears the reason
        latest.clear()
        latest.setPosition(position)
        switch state {
        case .idle, .denied, .restricted, .requestingAccess:
            return   // recorded; a pending prompt's answer configures the camera chosen last
        case .unavailable, .interrupted, .failed:
            stop()
            start()
        case .starting, .running:
            if session != nil, Self.camera(for: position) != nil {
                switchInput()
            } else {
                stop()
                start()   // no camera at the new position: `unavailable`, nothing asked
            }
        }
    }

    /// Replaces the running session's input with the chosen camera's (research CAM-002-D4).
    private func switchInput() {
        guard let session, let camera = Self.camera(for: position), let input = try? AVCaptureDeviceInput(device: camera) else {
            stop()
            state = .unavailable
            return
        }
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
            session.beginConfiguration()
            let old = session.inputs
            old.forEach(session.removeInput)
            let added = session.canAddInput(input)
            if added { session.addInput(input) } else { old.forEach { if session.canAddInput($0) { session.addInput($0) } } }
            session.commitConfiguration()
            video.async { [self] in   // every buffer queued before the swap was refused by the closed slot
                DispatchQueue.main.async { [self] in
                    guard current == generation, state == .starting else { return }
                    if added {
                        latest.open()
                        state = .running
                    } else {
                        stop()
                        state = .unavailable
                    }
                }
            }
        }
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

    // MARK: - Session

    private func configureAndRun() {
        state = .starting
        guard let camera = Self.camera(for: position), let input = try? AVCaptureDeviceInput(device: camera) else {
            state = .unavailable
            return
        }
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

    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard latest.isOpen, let cache, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let width = CVPixelBufferGetWidth(pixels), height = CVPixelBufferGetHeight(pixels)
        var wrapper: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, cache, pixels, nil, .bgra8Unorm_srgb, width, height, 0,
                                                        &wrapper) == kCVReturnSuccess,
              let wrapper, let texture = CVMetalTextureGetTexture(wrapper) else { return }
        latest.store(texture, owner: wrapper, position: Self.position(of: connection))
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
