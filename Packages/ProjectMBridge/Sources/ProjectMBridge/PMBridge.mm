// PMBridge.mm — Objective-C++ bridge over the libprojectM C API (task T069;
// contracts/projectm-bridge.md). See PMBridge.h for the guarantees.
//
// Exceptions: the C API is declared extern "C", but the engine is C++ and could still let an
// exception escape; every call is wrapped so none reaches Objective-C or Swift (guarantee 1).
// Preset failures: projectm_load_preset_file returns nothing; the engine reports a failure through
// the preset-switch-failed callback during the call, which this file records (guarantee 4).
#import "PMBridge.h"

#include <projectM-4/projectM.h>

#include <exception>
#include <pthread.h>

NSErrorDomain const PMEngineErrorDomain = @"PMEngineError";

static NSError *PMMakeError(PMEngineError code, NSString *description) {
    return [NSError errorWithDomain:PMEngineErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

static NSString *PMExceptionMessage(const std::exception &e) {
    return [NSString stringWithUTF8String:e.what()] ?: @"unknown engine exception";
}

/// GL_VERSION; glGetString returns NULL for it when no context is current.
static const unsigned int PMGLVersion = 0x1F02;
typedef const unsigned char *(*PMGLGetStringFn)(unsigned int);

@interface PMEngine ()
- (void)presetFailedWithMessage:(nullable const char *)message;
@end

/// Collects the engine's warning and error messages on this thread while a call runs, so a
/// failure's NSError can say why. Set per thread, only around engine creation and preset loads.
static void PMCollectLog(const char *message, projectm_log_level level, void *userData) {
    (void)level;
    if (message == NULL || userData == NULL) {
        return;
    }
    NSMutableArray<NSString *> *lines = (__bridge NSMutableArray<NSString *> *)userData;
    NSString *line = [NSString stringWithUTF8String:message];
    if (line) {
        [lines addObject:line];
    }
}

static NSString *PMJoin(NSArray<NSString *> *lines, NSString *fallback) {
    return lines.count > 0 ? [lines componentsJoinedByString:@" | "] : fallback;
}

static void PMPresetSwitchFailed(const char *presetFilename, const char *message, void *userData) {
    (void)presetFilename;
    PMEngine *engine = (__bridge PMEngine *)userData;
    [engine presetFailedWithMessage:message];
}

@implementation PMEngine {
    projectm_handle _handle;
    pthread_t _thread;
    BOOL _presetFailed;
    NSString *_presetFailureMessage;
}

#define PM_ASSERT_RENDER_THREAD() \
    NSAssert(pthread_equal(pthread_self(), _thread), @"PMEngine used off the thread that created it")

- (nullable instancetype)initWithGLLoader:(PMGLLoadProc)loadProc
                                 userData:(nullable void *)userData
                                    error:(NSError **)error {
    if (!(self = [super init])) {
        return nil;
    }
    _thread = pthread_self();
    PMGLGetStringFn getString = (PMGLGetStringFn)loadProc("glGetString", userData);
    if (getString == NULL || getString(PMGLVersion) == NULL) {
        if (error) {
            *error = PMMakeError(PMEngineErrorContextUnavailable, @"No current OpenGL ES context on this thread");
        }
        return nil;
    }
    NSString *failure = nil;
    NSMutableArray<NSString *> *log = [NSMutableArray array];
    projectm_set_log_callback(PMCollectLog, true, (__bridge void *)log);
    projectm_set_log_level(PROJECTM_LOG_LEVEL_WARN, true);
    try {
        _handle = projectm_create_with_opengl_load_proc(loadProc, userData);
    } catch (const std::exception &e) {
        failure = PMExceptionMessage(e);
    } catch (...) {
        failure = @"unknown engine exception";
    }
    projectm_set_log_callback(NULL, true, NULL);
    if (_handle == NULL) {
        if (error) {
            *error = PMMakeError(PMEngineErrorEngineCreateFailed,
                                 failure ?: PMJoin(log, @"projectm_create_with_opengl_load_proc returned NULL"));
        }
        return nil;
    }
    projectm_set_preset_switch_failed_event_callback(_handle, PMPresetSwitchFailed, (__bridge void *)self);
    return self;
}

- (void)dealloc {
    if (_handle == NULL) {
        return;
    }
    // The owner releases the engine on the render thread with the GL context current (guarantee 3).
    NSAssert(pthread_equal(pthread_self(), _thread), @"PMEngine released off its render thread");
    projectm_set_preset_switch_failed_event_callback(_handle, NULL, NULL);
    try {
        projectm_destroy(_handle);
    } catch (...) {
        // Nothing can be recovered while tearing down; never let it escape dealloc.
    }
    _handle = NULL;
}

- (void)setViewportWidth:(NSInteger)width height:(NSInteger)height {
    PM_ASSERT_RENDER_THREAD();
    if (width <= 0 || height <= 0) {
        return;
    }
    try {
        projectm_set_window_size(_handle, (size_t)width, (size_t)height);
    } catch (...) {
    }
}

- (void)addPCMInterleavedStereo:(const float *)samples frames:(NSUInteger)frames {
    PM_ASSERT_RENDER_THREAD();
    if (samples == NULL || frames == 0) {
        return;
    }
    NSUInteger count = MIN(frames, (NSUInteger)projectm_pcm_get_max_samples());
    try {
        projectm_pcm_add_float(_handle, samples, (unsigned int)count, PROJECTM_STEREO);
    } catch (...) {
    }
}

+ (NSUInteger)maxSamplesPerFrame {
    return projectm_pcm_get_max_samples();
}

- (BOOL)loadPresetAtPath:(NSString *)path smooth:(BOOL)smooth error:(NSError **)error {
    PM_ASSERT_RENDER_THREAD();
    _presetFailed = NO;
    _presetFailureMessage = nil;
    try {
        projectm_load_preset_file(_handle, path.fileSystemRepresentation, smooth);
    } catch (const std::exception &e) {
        _presetFailed = YES;
        _presetFailureMessage = PMExceptionMessage(e);
    } catch (...) {
        _presetFailed = YES;
        _presetFailureMessage = @"unknown engine exception";
    }
    if (_presetFailed) {
        if (error) {
            *error = PMMakeError(PMEngineErrorPresetLoadFailed,
                                 _presetFailureMessage ?: @"The preset could not be loaded");
        }
        return NO;
    }
    return YES;
}

- (void)renderFrameToFramebuffer:(uint32_t)fbo {
    PM_ASSERT_RENDER_THREAD();
    try {
        projectm_opengl_render_frame_fbo(_handle, fbo);
    } catch (...) {
    }
}

- (void)presetFailedWithMessage:(nullable const char *)message {
    _presetFailed = YES;
    _presetFailureMessage = message ? [NSString stringWithUTF8String:message] : nil;
}

@end
