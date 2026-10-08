#include <stdint.h>

// CMake defines calc_EXPORTS only when building calc as a shared library. Static
// builds leave exporting to the link hook, which only exports the symbols it keeps.
#if defined(_WIN32) && defined(calc_EXPORTS)
#define FFI_EXPORT __declspec(dllexport)
#else
#define FFI_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

FFI_EXPORT int32_t add(int32_t a, int32_t b);

FFI_EXPORT int32_t multiply(int32_t a, int32_t b);

#ifdef __cplusplus
}
#endif
