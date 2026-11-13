// CFlashLimiter.h — the strobe safety envelope post-pass for projectM frames (FX-019, ADR-0011;
// Reduce flashing FR-072, tasks T104, T119), shared by ANGLERenderer and the GLES fallback renderer.
// The decision rule is FlashSafety's `FlashEnvelope` (Packages/FlashSafety), ported to GLSL so it
// runs on the frame's own measured levels without a CPU read-back. All calls need the renderer's GL
// context current.
#ifndef CFLASHLIMITER_H
#define CFLASHLIMITER_H

/// Resolves a GL ES 3.0 entry point by name (same shape as the engine's load proc: eglGetProcAddress
/// for ANGLE, PMAppleGLESLoadProc for Apple's OpenGL ES).
typedef void *_Nullable (*PMFlashLoadProc)(const char *_Nonnull name, void *_Nullable userData);

/// One frame's limits (FlashSafety's `FlashEnvelopeConfiguration.limiterParameters(frameTime:)`).
typedef struct PMFlashEnvelopeParameters {
    float frameTime;            ///< seconds since the previous frame, already clamped (0…0.1)
    float window;               ///< sliding window, seconds (1)
    float luminanceThreshold;   ///< 0.10
    float rednessThreshold;     ///< 0.0625
    float gateMargin;           ///< 0.005
    float riseRatePerSecond;    ///< < 0: no rate limit
    int transitionBudget;       ///< 2…6
} PMFlashEnvelopeParameters;

typedef struct PMFlashLimiter PMFlashLimiter;
/// NULL if an entry point is missing or the shaders do not compile.
PMFlashLimiter *_Nullable PMFlashLimiterCreate(PMFlashLoadProc _Nonnull load, void *_Nullable userData);
void PMFlashLimiterDestroy(PMFlashLimiter *_Nullable limiter);
/// Forgets the envelope's history: the next frame is shown as it is.
void PMFlashLimiterReset(PMFlashLimiter *_Nonnull limiter);
/// The framebuffer the engine renders into this frame (sized width x height); 0 on failure. A new
/// size keeps the envelope's history.
unsigned int PMFlashLimiterBegin(PMFlashLimiter *_Nonnull limiter, int width, int height);
/// Measures the frame, updates the envelope and draws the frame × gain (0…1, linear light) into
/// `targetFramebuffer`.
void PMFlashLimiterFinish(PMFlashLimiter *_Nonnull limiter, unsigned int targetFramebuffer,
                          const PMFlashEnvelopeParameters *_Nonnull parameters);
/// The gain applied by the last Finish (tests; reads back one texel, so it waits for the GPU).
float PMFlashLimiterLastGain(PMFlashLimiter *_Nonnull limiter);
unsigned int PMFlashLimiterSceneFramebuffer(PMFlashLimiter *_Nonnull limiter);

#endif
