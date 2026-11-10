// PMGLESLoader.h — the engine's OpenGL ES load proc for Apple's OpenGL ES 3.0 (contract
// projectm-bridge.md; Constitution I: no dlsym). The table is generated from the iOS SDK by
// scripts/generate_gles_loader.py.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Resolves a GL entry point by name: same shape as the engine's `projectm_load_proc`.
typedef void *_Nullable (*PMGLLoadProc)(const char *name, void *_Nullable userData);

/// Returns the address of the OpenGL ES 3.0 function `name`, or NULL when it is not one of them.
/// Every address is a public function linked from OpenGLES.framework. `userData` is ignored.
FOUNDATION_EXPORT void *_Nullable PMAppleGLESLoadProc(const char *name, void *_Nullable userData);

/// Number of functions in the table (tests).
FOUNDATION_EXPORT NSUInteger PMAppleGLESFunctionCount(void);

NS_ASSUME_NONNULL_END
