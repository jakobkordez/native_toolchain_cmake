# native_toolchain_cmake demo add_link

This example splits building and linking across hooks:

- [hook/build.dart](hook/build.dart) builds the CMake project with `staticWhenLinking: true`.
  If linking is enabled, it builds a static library and routes it to the link hook,
  otherwise it builds a shared library and bundles it directly.
- [hook/link.dart](hook/link.dart) links the static library into a shared library with
  `CLinker` from [native_toolchain_c](https://pub.dev/packages/native_toolchain_c), keeping
  only `math_add`, the one function used from Dart.

```sh
# Linking disabled: the shared library is bundled as is.
dart test

# Linking enabled: the link hook runs and drops math_multiply.
dart build cli
./build/cli/<os>_<arch>/bundle/bin/add_link
```
