# Contract: ProjectM Bridge and Renderer

Packages: **ProjectMBridge** (Objective-C++ over the libprojectM C API) and **Rendering**
(`VisualizerRenderer` and its backends). Neither imports CaptureKit; they consume only
`NormalizedPCMReader`.

## PMBridge (Objective-C, Swift-visible)

```objc
NS_SWIFT_NAME(ProjectMEngine)
@interface PMEngine : NSObject
/// `loadProc` resolves GL ES entry points: a static table of linked ES 3.0 functions (Apple GL ES)
/// or `eglGetProcAddress` (ANGLE). No `dlsym` (Constitution I).
- (nullable instancetype)initWithGLLoader:(PMGLLoadProc)loadProc
                                 userData:(nullable void *)userData
                                    error:(NSError **)error;
- (void)setViewportWidth:(NSInteger)w height:(NSInteger)h;          // on resize/rotation (FR-041)
- (void)addPCMInterleavedStereo:(const float *)samples frames:(NSUInteger)frames; // ≤ maxSamples
@property (class, readonly) NSUInteger maxSamplesPerFrame;          // projectm_pcm_get_max_samples
- (BOOL)loadPresetAtPath:(NSString *)path smooth:(BOOL)smooth error:(NSError **)error; // FR-045
- (void)renderFrameToFramebuffer:(uint32_t)fbo;                     // projectm_opengl_render_frame_fbo
@end
```

Guarantees:

1. All C++ exceptions are caught inside `.mm` and mapped to `NSError` domain `PMEngineError`
   (`presetLoadFailed`, `contextUnavailable`, `engineCreateFailed`). None cross into Swift.
2. Every call happens on the render thread that owns the GL context. Calls from other threads are
   a programming error (asserted in debug builds).
3. `dealloc` destroys the projectM instance on the render thread before the GL context is
   released.
4. A failed preset load leaves the current preset running (FR-045).
5. The bridge maps 1:1 onto the documented C API (`projectm_create_with_opengl_load_proc`,
   `projectm_pcm_add_float`, `projectm_opengl_render_frame_fbo`, preset load calls). No engine
   patches.

## VisualizerRenderer (Rendering)

```swift
@MainActor public protocol VisualizerRenderer: AnyObject {
    var view: UIView { get }                         // hosted by SwiftUI via UIViewRepresentable
    func attach(pcm: NormalizedPCMReader)
    func setPreset(_ preset: Preset) async throws    // ≤ 1 s (SC-007)
    func pause(); func resume()                      // FR-046, FR-050
    var reduceFlashing: Bool { get set }             // FR-072
    var metrics: RenderMetrics { get }               // fps, frame time; feeds the FR-048 overlay
}
```

Backends: `GLESRenderer` (Apple OpenGL ES 3.0, Phase C prototype). `ANGLERenderer` (if ADR-0003
selects it). The display link drives frames. Each frame drains up to `maxSamplesPerFrame` from
`NormalizedPCMReader` into the engine, then renders.

Guarantees: lower frame rate or resolution under thermal/low-power pressure, never below 30 fps
(FR-049). `pause()` stops the display link within 1 frame.
