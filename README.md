# native_toolchain_cmake

A library to invoke CMake for Dart Native Assets.

## Status: Experimental

This library is experimental and may change without warning, use with caution!

## Example

Refer to [example](https://github.com/rainyl/native_toolchain_cmake/tree/main/example)

## Configuration

You can configure some options in your `pubspec.yaml`

```yaml
hooks:
  user_defines:
    <YOUR_PACKAGE_NAME_THAT_USES_NATIVE_TOOLCHAIN_CMAKE>: # e.g., dartcv4
      env_file: null # e.g., ".env"
      cmake_version: null # e.g., "3.22.1", if not specified, use the latest
      ninja_version: null # e.g., "1.10.2", if not specified, use the latest
      prefer_android_cmake: null # true or false, defaults to true for android
      prefer_android_ninja: null # true or false, defaults to true for android
      android:
        android_home: null # e.g., "C:\\Android\\Sdk" # can be set in .env file
        ndk_version: null # e.g., "28.2.13676358"
        cmake_version: null # e.g., "3.22.1", if not specified, fallback to global cmake_version
        # NOTE: Ninja is the default and only generator for Android
        ninja_version: null # e.g., "1.10.2", if not specified, fallback to global ninja_version
      ios:
        cmake_version: null # e.g., "3.22.1"
        # NOTE: you need to use Generator.ninja if you want to use Ninja for platforms except Android
        ninja_version: null # e.g., "1.10.2"
      windows:
        cmake_version: null # e.g., "3.22.1"
        ninja_version: null # e.g., "1.10.2"
      linux:
        cmake_version: null # e.g., "3.22.1"
        ninja_version: null # e.g., "1.10.2"
      macos:
        cmake_version: null # e.g., "3.22.1"
        ninja_version: null # e.g., "1.10.2"
```

## Link Hooks

A build hook can hand static libraries to a link hook (`hook/link.dart`) instead of bundling
them, so native code unused by the app can be dropped. See
[example/add_link](https://github.com/rainyl/native_toolchain_cmake/tree/main/example/add_link).

Linking is only enabled for `dart build cli` and Flutter profile and release builds. `dart run`,
`dart test` and Flutter debug builds bundle the build hook's output directly, so the build hook
has to handle both cases.

1. Build static libraries when linking is enabled and shared libraries otherwise. This sets
   `BUILD_SHARED_LIBS`, so declare the library without `SHARED`, e.g. `add_library(add src/add.c)`.
   It also turns on position independent code and per-function sections (CMake 3.15+).

   ```dart
   final installDir = input.outputDirectory.resolve('install/');
   await CMakeBuilder.create(
     name: 'add',
     sourceDir: input.packageRoot.resolve('src/'),
     defines: {'CMAKE_INSTALL_PREFIX': installDir.toFilePath()},
     targets: ['install'],
     staticWhenLinking: true,
   ).run(input: input, output: output);
   ```

2. Route the static libraries to the link hook:

   ```dart
   final linking = input.config.linkingEnabled;
   await output.findAndAddCodeAssets(
     input,
     outDir: installDir,
     names: {'add': 'add.dart'},
     linkMode: linking ? StaticLinking() : null,
     routing: linking ? ToLinkHook(input.packageName) : const ToAppBundle(),
   );
   ```

3. Link them into a shared library in `hook/link.dart`, e.g. with `CLinker` from
   [native_toolchain_c](https://pub.dev/packages/native_toolchain_c):

   ```dart
   await link(args, (input, output) async {
     await CLinker.library(
       name: 'add',
       assetName: 'add.dart', // same asset id as in the build hook
       sources: [for (final library in input.assets.code) library.file!.toFilePath()],
       linkerOptions: LinkerOptions.treeshake(symbolsToKeep: ['add']),
       flags: [if (input.config.code.targetOS == OS.windows) '/MD'],
     ).run(input: input, output: output);
   });
   ```

Things to keep in mind when linking with `CLinker`:

- It uses its own compiler (`input.config.code.cCompiler` or what it finds on the host), not the
  CMake toolchain. On Linux, CMake builds with GCC by default. For C++ libraries, pass
  `language: Language.cpp` and the matching `cppLinkStdLib`.
- Pass every static library the shared library needs, including third-party ones the CMake
  project builds, and system libraries via `libraries`.
- On Windows it supports MSVC only. It exports the kept symbols through a generated `.def` file.
  With `symbolsToKeep: null` (keep all), only symbols marked `__declspec(dllexport)` are exported.
- On Windows it links against the static C runtime unless `/MD` is passed, while CMake compiles
  with the dynamic one by default.

## NDK Discovery

When targeting Android, the NDK root directory is resolved in the following
order (aligned with the Flutter tool's
[AndroidSdk.locateAndroidSdk](https://github.com/flutter/flutter/blob/master/packages/flutter_tools/lib/src/android/android_sdk.dart)):

### SDK Root

1. `user_defines.android.android_home` (if set in `pubspec.yaml`)
2. `ANDROID_HOME` environment variable
3. Platform-default install location:
   - Linux:   `$HOME/Android/Sdk`
   - macOS:   `$HOME/Library/Android/sdk`
   - Windows: `%USERPROFILE%\AppData\Local\Android\Sdk`
4. `<dir>/sdk` fallback (for each hit above: if the directory itself is not a
   valid SDK but `<dir>/sdk` is, that subdirectory is used).
5. `aapt` on PATH → `parent.parent.parent` if it looks like an SDK root.
6. `adb` on PATH → `parent.parent` if it looks like an SDK root.

A directory qualifies as an SDK root if it contains a `platform-tools/` or
`licenses/` subdirectory.

### NDK Root

For each SDK root found above:

1. `ANDROID_NDK_HOME` (exact NDK root — highest priority)
2. `ANDROID_NDK_PATH` (fallback when `ANDROID_NDK_HOME` is unset)
3. `ANDROID_NDK_ROOT` (additional fallback)
4. `<sdk>/ndk/<version>/` directories sorted by `Version.parse` in descending
   order (latest first; entries that cannot be parsed as a [Version] are
   skipped).
5. Linux-only legacy `<sdk>/ndk-bundle/` (single-NDK layout).
6. `ndk-build` on PATH → parent directory (lowest priority).

If `user_defines.android.ndk_version` is specified, only NDK roots whose
basename parses to the requested version are kept; candidates without a
parseable basename (e.g. `ANDROID_NDK_HOME` pointing at a custom-named
directory, or `ndk-bundle`) are skipped.

## Acknowledgements

- [native_toolchain_c](https://pub.dev/packages/native_toolchain_c)

## License

Apache-2.0 License
