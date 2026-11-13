// AVCameraFrameProvider.swift — the rear camera through AVFoundation (CAM-001-R4, R6 to R9, R15;
// research CAM-001-D2, D4, D5). iOS only.
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
//   `failed`. `stop()` closes the slot at once (no picture is shown or kept from then on), stops
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

    public private(set) var state: CameraFeedState = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    public var onStateChange: ((CameraFeedState) -> Void)?

    public init(device: MTLDevice) {
        self.device = device
        super.init()
    }

    /// The back wide-angle camera, if this device has one.
    public static func backCamera() -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    public func start() {
        guard session == nil, state != .requestingAccess, state != .starting else { return }
        generation &+= 1
        let current = generation
        guard Self.backCamera() != nil else {   // checked first: no camera, no prompt (CAM-001-R6)
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
        state = .idle
    }

    public func latestFrame() -> CameraFrame? { latest.read() }

    // MARK: - Session

    private func configureAndRun() {
        state = .starting
        guard let camera = Self.backCamera(), let input = try? AVCaptureDeviceInput(device: camera) else {
            state = .unavailable
            return
        }
        var newCache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &newCache) == kCVReturnSuccess, let newCache else {
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

        let coordinator = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: nil)
        rotationCoordinator = coordinator
        latest.setRotation(CameraRotation(degrees: Double(coordinator.videoRotationAngleForHorizonLevelCapture)))
        let slot = latest
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.new]) { coordinator, _ in
            slot.setRotation(CameraRotation(degrees: Double(coordinator.videoRotationAngleForHorizonLevelCapture)))
        }
        observe(session)

        latest.open()
        let current = generation
        let box = Unchecked(value: session)
        sessionQueue.async { [self] in
            box.value.startRunning()
            let running = box.value.isRunning
            DispatchQueue.main.async { [self] in
                guard current == generation, state == .starting else { return }
                state = running ? .running : .failed
            }
        }
    }

    private func observe(_ session: AVCaptureSession) {
        let center = NotificationCenter.default
        let current = generation
        observers.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main) {
            [self] _ in
            guard current == generation, state == .running || state == .starting else { return }
            latest.clear()
            state = .interrupted
        })
        observers.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: .main) {
            [self] _ in
            guard current == generation, state == .interrupted else { return }
            state = .running
        })
        observers.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) {
            [self] _ in
            guard current == generation, state != .idle else { return }
            latest.clear()
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
        latest.store(texture, owner: wrapper)
    }
}
#endif
