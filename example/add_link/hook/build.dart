import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';

void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;

    final installDir = input.outputDirectory.resolve('install/');
    await CMakeBuilder.create(
      name: 'add_link',
      sourceDir: input.packageRoot.resolve('src/'),
      defines: {'CMAKE_INSTALL_PREFIX': installDir.toFilePath()},
      targets: ['install'],
      // Static libraries if linking is enabled, shared libraries otherwise.
      staticWhenLinking: true,
    ).run(input: input, output: output);

    // With linking enabled, hand the static library to hook/link.dart instead of bundling it.
    final linking = input.config.linkingEnabled;
    await output.findAndAddCodeAssets(
      input,
      outDir: installDir,
      names: {'add_link': 'add_link.dart'},
      linkMode: linking ? StaticLinking() : null,
      routing: linking ? ToLinkHook(input.packageName) : const ToAppBundle(),
    );
  });
}
