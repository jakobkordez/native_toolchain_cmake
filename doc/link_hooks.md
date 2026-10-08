# Link hook support

Status as of 2026-10-08, targeting the unreleased 0.3.3. For usage, see the
[Link Hooks section in the README](../README.md#link-hooks) and
[example/add_link](../example/add_link).

## Why

A package's build hook can send static libraries to its own link hook (`hook/link.dart`)
instead of bundling a shared library. The link hook runs after the Dart code is compiled, so it
can link only the native symbols the app actually uses (tree-shaking). For large CMake projects
such as OpenCV, this could cut binary size a lot.

## How hooks split building and linking

These facts come from `package:hooks` 2.2.0, `package:code_assets` 2.1.0, Dart 3.13 and current
Flutter.

- `input.config.linkingEnabled` tells the build hook whether a link hook will run:

  | Command | Linking enabled |
  |---|---|
  | `dart run`, `dart test` | No |
  | `dart build cli` | Yes |
  | Flutter debug | No |
  | Flutter profile, release, jit-release | Yes |

  A build hook therefore has to handle both cases.
- The build hook routes a `CodeAsset` with `linkMode: StaticLinking()` using
  `output.assets.code.add(asset, routing: ToLinkHook(input.packageName))`. Routing to a link hook
  while linking is disabled fails `package:hooks` output validation.
- The SDKs always set `LinkModePreference.dynamic`. `code_assets` only checks link mode against
  that preference for bundled assets, so static assets routed to a link hook are accepted.
- The link hook reads the static libraries from `input.assets.code`. It must emit a
  `DynamicLoadingBundled` asset with the same asset id the `@Native` bindings use, because the
  SDKs don't support `StaticLinking` in the app bundle.
- The symbols to keep normally come from `input.recordedUses` (package:record_use, on by
  default since Dart 3.13), mapped to C symbol names. ffigen can generate that mapping.

## How native_toolchain_c does it

Based on native_toolchain_c 0.19.5.

- **Build hook:** `CBuilder.run(routing: List<AssetRouting>, linkModePreference: ...)` builds
  `libX.a` or `X.lib` and emits it as a `StaticLinking` asset routed to the link hook.
- **Link hook:** `CLinker.library(...).run(input: linkInput, output: ...)` links the archives,
  passed as `sources`, through the C compiler driver. It takes the compiler from
  `input.config.code.cCompiler` or finds one on the host. It emits one `DynamicLoadingBundled`
  asset and adds the archives as dependencies.
- **`LinkerOptions.treeshake(symbolsToKeep: ...)`** turns the symbol list into per-OS linker
  flags:

  | Target | Flags |
  |---|---|
  | Linux, Android | `--whole-archive` around the inputs, `-u sym`, `--gc-sections`, a generated `--version-script` |
  | macOS, iOS | `-u _sym`, `-dead_strip`, a generated `-exported_symbols_list` (`-force_load` when keeping everything) |
  | Windows | `cl.exe` only. `/INCLUDE:sym`, a generated `/DEF:` with `EXPORTS`, `/OPT:REF` (`/WHOLEARCHIVE` when keeping everything) |

  `symbolsToKeep: null` keeps everything. `[]` produces no library at all.
- **`CLibrary`** (new in 0.18.0) is declared once in `lib/src/` and used from both hooks:
  - `build()` builds static libraries routed to the link hook when linking is enabled, and a
    bundled shared library otherwise.
  - `link()` collects the routed assets and runs `CLinker`.
- **Reference examples** live in dart-lang/native under `pkgs/code_assets/example/` (sqlite,
  mini_audio, stb_image) and `pkgs/hooks_runner/test_data/treeshaking_*`.

## What this package does (step 1)

### `CMakeBuilder.staticWhenLinking`

It is opt-in and `false` by default. When it is set:

- **Linking enabled:**
  - `-DBUILD_SHARED_LIBS=OFF`
  - `-DCMAKE_POSITION_INDEPENDENT_CODE=ON`
  - `-DCMAKE_PROJECT_INCLUDE=<package>/cmake/static_for_linking.cmake`. The included file
    appends compiler flags so the link hook can drop unused functions one by one:

    | Compiler | Flags added |
    |---|---|
    | GCC, Clang | `-ffunction-sections -fdata-sections` |
    | MSVC, clang-cl | `/Gy /Gw` |
    | AppleClang | None; ld64 strips per symbol already |

    This needs CMake 3.15 or newer.
- **Linking disabled:** `-DBUILD_SHARED_LIBS=ON`. The same `add_library()` without `SHARED` then
  builds a shared library to bundle.
- **Precedence:** these are passed before the user's `defines`, so user defines override them.
- **Build folders:** with `buildLocal`, static builds go to `build/<os>/<arch>-static`. The
  default hook output directory already differs between linking modes, because it is a
  checksum of the whole config.
- **`runStandalone(linkingEnabled: ...)`** defaults to `input.config.linkingEnabled`.

Implementation: [builder.dart](../lib/src/builder/builder.dart),
[run_builder.dart](../lib/src/builder/run_builder.dart),
[static_for_linking.cmake](../cmake/static_for_linking.cmake).

### Asset helpers

In [add_assets.dart](../lib/src/utils/add_assets.dart):

- `findCodeAssets` and `findAndAddCodeAssets` take `linkMode: LinkMode?`. It overrides the mode
  derived from the preference and decides the expected file name, e.g. `libadd.a`.
- `findAndAddCodeAssets`, `addCodeAsset` and `addAllCodeAssets` take
  `routing: AssetRouting = const ToAppBundle()`.
- Duplicate checks apply per routing, so the same asset can be bundled and routed to a link
  hook. `addedAssetIds` still returns the ids bundled into the app, as before.

### Example and tests

- [example/add_link](../example/add_link): the build hook uses `staticWhenLinking` and routes the
  library to the link hook. The link hook uses `CLinker` with
  `LinkerOptions.treeshake(symbolsToKeep: ['math_add'])`.
- [test/builder/cmake_builder_link_test.dart](../test/builder/cmake_builder_link_test.dart):
  - A static CMake build, routed to the link hook, then a `CLinker` tree-shake. The result
    exports `add` and not `multiply`.
  - The linking-disabled path, which builds a shared library.
- [test/utils/add_assets_test.dart](../test/utils/add_assets_test.dart), group `link hook`: tests
  for routing, the link mode override and per-routing duplicate checks.
- `native_toolchain_c` is a dev dependency only. Making it a regular dependency would force
  `code_assets ^2.1.0` and drop the 1.x compatibility kept in 0.3.2.

## Compared to native_toolchain_c

| | native_toolchain_c | native_toolchain_cmake |
|---|---|---|
| Build static libraries when linking | `CLibrary`: automatic. `CBuilder`: `linkModePreference` | `staticWhenLinking: true` |
| Emitting the asset | `CBuilder.run` emits it, `assetName` set on the builder | A separate `findAndAddCodeAssets` call, since CMake outputs are only known after the build |
| Link mode parameter | `LinkModePreference?` | `LinkMode?` |
| Routing parameter | `List<AssetRouting>` | A single `AssetRouting` |
| Routing to a link hook while linking is off | `assert` in `CBuilder.run` | Caught by hooks output validation after the hook finishes |
| Link hook | `CLinker` / `CLibrary.link()` | None of our own; use `CLinker` |
| One definition shared by both hooks | Yes (`CLibrary`) | No; names are repeated in both hooks |
| Tree-shaking granularity | Per source file on Linux/Android; per function on Apple and MSVC | Per function everywhere |

## Caveats when linking with CLinker

The README lists these for users. They matter for the design here, because CMake builds the
archives but `CLinker` links them:

- **Compiler:** `CLinker` doesn't use our CMake toolchain. It may pick a different compiler,
  e.g. gcc on Linux for the build vs. its own pick for the link, or a different NDK on Android.
- **Libraries:** every archive the shared library needs has to be passed explicitly, including
  third-party ones. On Linux and Android all of them are linked with `--whole-archive`.
- **Windows exports:** with keep-all (`symbolsToKeep: null`), only symbols marked
  `__declspec(dllexport)` are exported, because no `.def` file is generated.
- **Windows C runtime:** `CLinker` links the static C runtime (`/LD` implies `/MT`) unless `/MD`
  is passed. CMake compiles with `/MD` by default.

## Verification status

**Verified** on Windows 11 with MSVC 2019 (16.11), CMake 3.23 and Dart 3.13.4:

- All new tests pass.
- Full suite: 133 pass. The 24 failures are Android/NDK and Windows ARM64 cross-compile tests,
  failing because those tools aren't installed on that machine.
- `example/add_link`:
  - `dart test` bundles a shared library.
  - `dart build cli` builds a static `.lib`. The link hook's DLL exports only `math_add`, and
    the built executable runs.

**Not verified:**

- Linux and macOS. CI's `dart test` will run the new linking test there for the first time.
- Android and iOS. No Flutter example uses a link hook yet.

## Issues found along the way

These predate this feature.

1. **Fixed.** [env_from_bat.dart](../lib/src/utils/env_from_bat.dart) ran `vcvars*.bat` by bare
   file name. That failed when `NoDefaultCurrentDirectoryInExePath` is set, because cmd then
   doesn't search the working directory. It now runs `.\vcvars*.bat`.
2. **Open.** With `buildLocal`, the build folder URI has no trailing slash, so
   `outDir.resolve('CMakeCache.txt')` points one folder up (`build/linux/` instead of
   `build/linux/x64/`). As a result:
   - `skipGenerateIfCached` never takes effect with `buildLocal`.
   - Different architectures share one `ntc_last_generate_status.txt`.
3. **Open.** With an explicit `outDir`, static and shared builds share one CMake cache. Combined with
   `skipGenerateIfCached`, switching linking modes skips the configure step that would change
   `BUILD_SHARED_LIBS`. Use a different `outDir` per mode.

## Open decision before releasing 0.3.3

Should the helper parameters match `CBuilder.run` exactly? That would mean
`linkModePreference: LinkModePreference?` instead of `linkMode: LinkMode?`, and `routing` as a
`List<AssetRouting>`. It is free now and a breaking change after release. Finding files only
needs "static" or "dynamic", so a preference is enough.

## Next steps

1. **Finish step 1:**
   - Decide on the parameter names above.
   - Fix the open issues above.
   - Add `dart build cli` for `example/add_link` to the examples CI on Windows, Linux and macOS.
2. **Try the step 1 pattern on a real multi-library C++ project**, e.g. dartcv4/OpenCV, before
   designing step 2. It should answer three questions:
   - Does `CLinker` cope with many archives (third-party included) being whole-archived?
   - Do C++ archives built by gcc or our NDK link cleanly with the compiler `CLinker` picks?
   - How much size does tree-shaking save with symbols from `input.recordedUses`?
3. **Add a `CMakeLibrary` with `build()` and `link()`**, declared once like `CLibrary`. Unless
   step 2 shows `CLinker` is good enough, link with CMake:
   - The link hook generates a small CMake project that imports the build hook's installed
     targets with `find_package`.
   - That project builds one `SHARED` library with tree-shaking flags ported from
     `LinkerOptions`.
   - This keeps the same toolchain, NDK, C runtime and library dependencies, and avoids
     depending on `native_toolchain_c`.
   - It requires the user's project to export its targets (`install(EXPORT ...)`). `CLinker`
     stays the documented fallback.
4. **Add an end-to-end record-use example** (ffigen bindings plus `input.recordedUses`), so
   symbol lists don't have to be maintained by hand.
