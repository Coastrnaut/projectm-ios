// CFlashLimiter.h — the "Reduce flashing" post-pass (tasks T104, T119; FR-072), shared by
// ANGLERenderer and the GLES fallback renderer. All calls need the renderer's GL context current.
#ifndef CFLASHLIMITER_H
#define CFLASHLIMITER_H

/// Resolves a GL ES 3.0 entry point by name (same shape as the engine's load proc: eglGetProcAddress
/// for ANGLE, PMAppleGLESLoadProc for Apple's OpenGL ES).
typedef void *_Nullable (*PMFlashLoadProc)(const char *_Nonnull name, void *_Nullable userData);

typedef struct PMFlashLimiter PMFlashLimiter;
/// NULL if an entry point is missing or the shaders do not compile.
PMFlashLimiter *_Nullable PMFlashLimiterCreate(PMFlashLoadProc _Nonnull load, void *_Nullable userData);
void PMFlashLimiterDestroy(PMFlashLimiter *_Nullable limiter);
/// Starts over from the next frame's brightness (no ramp from a stale value).
void PMFlashLimiterReset(PMFlashLimiter *_Nonnull limiter);
/// The framebuffer the engine renders into this frame (sized width x height); 0 on failure.
unsigned int PMFlashLimiterBegin(PMFlashLimiter *_Nonnull limiter, int width, int height);
/// Draws the limited frame into `targetFramebuffer`; the mean luminance moves at most `maxStep`.
void PMFlashLimiterFinish(PMFlashLimiter *_Nonnull limiter, unsigned int targetFramebuffer, float maxStep);
/// The adapted mean luminance after the last Finish (tests; reads back one pixel).
float PMFlashLimiterAdaptedLuminance(PMFlashLimiter *_Nonnull limiter);
unsigned int PMFlashLimiterSceneFramebuffer(PMFlashLimiter *_Nonnull limiter);

#endif
