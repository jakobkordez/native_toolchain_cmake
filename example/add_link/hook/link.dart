import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart';

void main(List<String> args) async {
  await link(args, (input, output) async {
    // The static libraries routed here by hook/build.dart.
    final staticLibraries = input.assets.code.toList();
    if (staticLibraries.isEmpty) return;

    await CLinker.library(
      name: 'add_link',
      // Same asset id as in hook/build.dart, which the @Native bindings use.
      assetName: 'add_link.dart',
      sources: [for (final library in staticLibraries) library.file!.toFilePath()],
      // Keep only the symbols used from Dart, derive them from `input.recordedUses` to follow
      // the Dart code automatically. `symbolsToKeep: null` keeps all of them, but on Windows
      // then only exports symbols marked `__declspec(dllexport)`.
      linkerOptions: LinkerOptions.treeshake(symbolsToKeep: ['math_add']),
      // CMake compiles with the dynamic C runtime on Windows, CLinker defaults to the static one.
      flags: [if (input.config.code.targetOS == OS.windows) '/MD'],
    ).run(input: input, output: output);
  });
}
