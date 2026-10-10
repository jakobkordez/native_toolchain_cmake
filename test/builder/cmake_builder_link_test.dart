@OnPlatform({'mac-os': Timeout.factor(2), 'windows': Timeout.factor(10)})
import 'dart:ffi';
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_c/native_toolchain_c.dart' show CLinker, LinkerOptions;
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';
import 'package:test/test.dart';

import '../helpers.dart';

const name = 'calc';

void main() {
  final targetOS = OS.current;
  final macOSConfig = targetOS == OS.macOS ? MacOSCodeConfig(targetVersion: defaultMacOSVersion) : null;
  final sourceDir = Directory('test/builder/testfiles/calc').absolute.uri;

  CodeAssetExtension codeAssetExtension() => CodeAssetExtension(
    targetOS: targetOS,
    macOS: macOSConfig,
    targetArchitecture: Architecture.current,
    // The Dart and Flutter SDKs always prefer dynamic, also when linking.
    linkModePreference: LinkModePreference.dynamic,
    cCompiler: cCompiler,
  );

  CMakeBuilder calcBuilder(BuildInput input) => CMakeBuilder.create(
    name: name,
    sourceDir: sourceDir,
    defines: {'CMAKE_INSTALL_PREFIX': input.outputDirectory.resolve('install').toFilePath()},
    targets: ['install'],
    staticWhenLinking: true,
  );

  Future<String> cFlags(BuildInput input) =>
      File.fromUri(input.outputDirectory.resolve('c_flags.txt')).readAsString();

  test('CMakeBuilder-staticWhenLinking builds static libraries for the link hook', () async {
    final tempUri = await tempDirForTest();
    final tempUriShared = await tempDirForTest();

    final buildInputBuilder = BuildInputBuilder()
      ..setupShared(
        packageName: name,
        packageRoot: tempUri,
        outputFile: tempUri.resolve('output.json'),
        outputDirectoryShared: tempUriShared,
      )
      ..config.setupBuild(linkingEnabled: true)
      ..addExtension(codeAssetExtension());
    final buildInput = BuildInput(buildInputBuilder.json);
    final buildOutputBuilder = BuildOutputBuilder();

    await calcBuilder(buildInput).run(input: buildInput, output: buildOutputBuilder, logger: logger);

    final installLib = buildInput.outputDirectory.resolve('install/lib/');
    expect(await File.fromUri(installLib.resolve(targetOS.staticlibFileName(name))).exists(), true);
    expect(await File.fromUri(installLib.resolve(targetOS.dylibFileName(name))).exists(), false);
    final flags = await cFlags(buildInput);
    switch (targetOS) {
      case OS.windows:
        expect(flags, contains('/Gy /Gw'));
      case OS.macOS:
        // AppleClang, ld64 strips per symbol already.
        expect(flags, isNot(contains('-ffunction-sections')));
      default:
        expect(flags, contains('-ffunction-sections -fdata-sections'));
    }

    final added = await buildOutputBuilder.findAndAddCodeAssets(
      buildInput,
      outDir: installLib,
      names: {name: '$name.dart'},
      linkModePreference: LinkModePreference.static,
      routing: const ToLinkHook(name),
      logger: logger,
    );
    expect(added, hasLength(1));

    final buildOutput = BuildOutput(buildOutputBuilder.json);
    expect(buildOutput.assets.encodedAssets, isEmpty);
    final assetsForLinking = buildOutput.assets.encodedAssetsForLinking[name]!;
    expect(assetsForLinking, hasLength(1));
    expect(CodeAsset.fromEncoded(assetsForLinking.single).linkMode, StaticLinking());

    // What a hook/link.dart would do with the static library.
    final linkInputBuilder = LinkInputBuilder()
      ..setupShared(
        packageName: name,
        packageRoot: tempUri,
        outputFile: tempUri.resolve('link_output.json'),
        outputDirectoryShared: tempUriShared,
      )
      ..setupLink(assets: assetsForLinking, assetsFromLinking: [], recordedUsesFile: null)
      ..addExtension(codeAssetExtension());
    final linkInput = LinkInput(linkInputBuilder.json);
    final linkOutputBuilder = LinkOutputBuilder();

    await CLinker.library(
      name: name,
      assetName: '$name.dart',
      sources: [for (final asset in linkInput.assets.code) asset.file!.toFilePath()],
      linkerOptions: LinkerOptions.treeshake(symbolsToKeep: ['add']),
      // Same C runtime as CMake's default.
      flags: [if (targetOS == OS.windows) '/MD'],
    ).run(input: linkInput, output: linkOutputBuilder, logger: logger);

    final linkOutput = LinkOutput(linkOutputBuilder.json);
    final dylibAsset = linkOutput.assets.code.single;
    expect(dylibAsset.id, 'package:$name/$name.dart');
    expect(dylibAsset.linkMode, DynamicLoadingBundled());

    final dylib = openDynamicLibraryForTest(dylibAsset.file!.toFilePath());
    final add = dylib.lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>('add');
    expect(add(1, 2), 3);
    expect(dylib.providesSymbol('multiply'), false);
  });

  test('CMakeBuilder-staticWhenLinking builds shared libraries when linking is disabled', () async {
    final tempUri = await tempDirForTest();
    final tempUriShared = await tempDirForTest();

    final buildInputBuilder = BuildInputBuilder()
      ..setupShared(
        packageName: name,
        packageRoot: tempUri,
        outputFile: tempUri.resolve('output.json'),
        outputDirectoryShared: tempUriShared,
      )
      ..config.setupBuild(linkingEnabled: false)
      ..addExtension(codeAssetExtension());
    final buildInput = BuildInput(buildInputBuilder.json);
    final buildOutputBuilder = BuildOutputBuilder();

    await calcBuilder(buildInput).run(input: buildInput, output: buildOutputBuilder, logger: logger);

    expect(await cFlags(buildInput), isNot(anyOf(contains('-ffunction-sections'), contains('/Gy'))));
    final added = await buildOutputBuilder.findAndAddCodeAssets(
      buildInput,
      outDir: buildInput.outputDirectory.resolve('install/'),
      names: {name: '$name.dart'},
      logger: logger,
    );
    expect(added.single.linkMode, DynamicLoadingBundled());
    expect(BuildOutput(buildOutputBuilder.json).assets.encodedAssetsForLinking, isEmpty);

    final dylib = openDynamicLibraryForTest(added.single.file!.toFilePath());
    final multiply = dylib.lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>('multiply');
    expect(multiply(2, 3), 6);
  });
}
