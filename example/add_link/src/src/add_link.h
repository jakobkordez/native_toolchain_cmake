#include <stdint.h>

// CMake defines add_link_EXPORTS only when building add_link as a shared library.
// Static builds leave exporting to hook/link.dart, which only exports the symbols it keeps.
#if defined(_WIN32) && defined(add_link_EXPORTS)
#define FFI_EXPORT __declspec(dllexport)
#else
#define FFI_EXPORT
#endif

#ifdef __cplusplus
extern "C" {
#endif

FFI_EXPORT int32_t math_add(int32_t a, int32_t b);

// Not used from Dart, so hook/link.dart drops it.
FFI_EXPORT int32_t math_multiply(int32_t a, int32_t b);

#ifdef __cplusplus
}
#endif
