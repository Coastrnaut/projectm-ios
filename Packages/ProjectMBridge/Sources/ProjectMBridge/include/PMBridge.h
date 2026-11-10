// PMBridge.h — Objective-C bridge over the libprojectM C API (task T069; contracts/projectm-bridge.md).
//
// Guarantees (contract):
//  1. Every C++ exception is caught in PMBridge.mm and mapped to an NSError in PMEngineErrorDomain
//     (presetLoadFailed, contextUnavailable, engineCreateFailed); none reaches Swift.
//  2. Every call happens on the thread that created the engine (the render thread that owns the
//     GL context); calls from other threads are asserted in debug builds.
//  3. dealloc destroys the projectM instance; the owner releases the engine on the render thread,
//     with its GL context current, before releasing the context.
//  4. A failed preset load leaves the current preset running (FR-045).
//  5. 1:1 mapping onto the documented C API; no engine patches beyond docs/projectm-patches.md.
#import <Foundation/Foundation.h>
#import "PMGLESLoader.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const PMEngineErrorDomain;

typedef NS_ERROR_ENUM(PMEngineErrorDomain, PMEngineError) {
    /// The preset file could not be read or parsed; the previous preset keeps running.
    PMEngineErrorPresetLoadFailed = 1,
    /// No current GL context on this thread.
    PMEngineErrorContextUnavailable = 2,
    /// projectm_create_with_opengl_load_proc failed or threw.
    PMEngineErrorEngineCreateFailed = 3,
};

/// Receives the engine's log messages: projectm_log_level values (1 trace … 6 fatal).
typedef void (^PMEngineLogHandler)(NSString *message, NSInteger level);

NS_SWIFT_NAME(ProjectMEngine)
@interface PMEngine : NSObject

/// Forwards every engine log message at `minimumLevel` or above, from any thread, to `handler`
/// (nil removes it). For diagnostics, e.g. RendererLab's library-loading record (T072).
+ (void)setLogHandler:(nullable PMEngineLogHandler)handler minimumLevel:(NSInteger)minimumLevel;

/// Creates the engine on the calling thread, which must have a current GL context. `loadProc`
/// resolves GL entry points (PMAppleGLESLoadProc for Apple's OpenGL ES, eglGetProcAddress for ANGLE).
- (nullable instancetype)initWithGLLoader:(PMGLLoadProc)loadProc
                                 userData:(nullable void *)userData
                                    error:(NSError **)error NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// On resize and rotation (FR-041).
- (void)setViewportWidth:(NSInteger)width height:(NSInteger)height;

/// Adds interleaved stereo Float32 frames (at most `maxSamplesPerFrame` per call).
- (void)addPCMInterleavedStereo:(const float *)samples frames:(NSUInteger)frames;

/// projectm_pcm_get_max_samples: the most frames the engine takes per call.
@property (class, readonly) NSUInteger maxSamplesPerFrame;

/// Loads a preset file. On failure returns NO with PMEngineErrorPresetLoadFailed and the previous
/// preset keeps running (FR-045).
- (BOOL)loadPresetAtPath:(NSString *)path smooth:(BOOL)smooth error:(NSError **)error;

/// Length of the blend into a newly loaded preset, in seconds (projectm_set/get_soft_cut_duration).
@property (nonatomic) double softCutDuration;

/// Renders one frame into the framebuffer object `fbo` (projectm_opengl_render_frame_fbo).
- (void)renderFrameToFramebuffer:(uint32_t)fbo;

@end

NS_ASSUME_NONNULL_END
