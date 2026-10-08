@OnPlatform({'mac-os': Timeout.factor(2), 'windows': Timeout.factor(10)})
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  const name = 'hello_world';
  const sourceDir = 'test/builder/testfiles/hello_world';

  for (final buildLocal in [false, true]) {
    test('CMakeBuilder skipGenerateIfCached${testSuffix([if (buildLocal) 'buildLocal'])}', () async {
      final tempUri = await tempDirForTest();
      final tempUri2 = await tempDirForTest();

      final logMessages = <String>[];
      final logger = createCapturingLogger(logMessages);

      final buildInputBuilder = BuildInputBuilder()
        ..setupShared(
          packageName: name,
          packageRoot: tempUri,
          outputFile: tempUri.resolve('output.json'),
          outputDirectoryShared: tempUri2,
        )
        ..config.setupBuild(linkingEnabled: false)
        ..addExtension(
          CodeAssetExtension(
            targetOS: OS.current,
            macOS: OS.current == OS.macOS ? MacOSCodeConfig(targetVersion: defaultMacOSVersion) : null,
            targetArchitecture: Architecture.current,
            linkModePreference: LinkModePreference.dynamic,
            cCompiler: cCompiler,
          ),
        );

      final buildInput = BuildInput(buildInputBuilder.json);
      final buildOutput = BuildOutputBuilder();

      // buildLocal builds next to the sources, so build a copy of them.
      final sourceUri = buildLocal
          ? await copyDirectory(Directory(sourceDir), Directory.fromUri(tempUri.resolve('src/')))
          : Directory(sourceDir).absolute.uri;

      final builder = CMakeBuilder.create(
        name: name,
        sourceDir: sourceUri,
        buildMode: BuildMode.release,
        androidArgs: const AndroidBuilderArgs(),
        appleArgs: const AppleBuilderArgs(),
        buildLocal: buildLocal,
      );

      // First run: Generate and build
      await builder.run(input: buildInput, output: buildOutput, logger: logger, skipGenerateIfCached: false);

      // Verify first run logs DO NOT contain the skip message
      expect(logMessages, isNot(contains(contains('CMake project is already successfully generated'))));

      // Clear logs for second run
      logMessages.clear();

      // Second run: Skip generate if cached
      await builder.run(input: buildInput, output: buildOutput, logger: logger, skipGenerateIfCached: true);

      // Verify second run logs DO contain the skip message
      expect(
        logMessages,
        contains(
          contains(
            'CMake project is already successfully generated and skipGenerateIfCached is requested, skip generating.',
          ),
        ),
      );
    });
  }

  test('CMakeBuilder skipGenerateIfCached generates again if the command changed', () async {
    final tempUri = await tempDirForTest();
    final tempUri2 = await tempDirForTest();

    final logMessages = <String>[];
    final logger = createCapturingLogger(logMessages);

    final buildInputBuilder = BuildInputBuilder()
      ..setupShared(
        packageName: name,
        packageRoot: tempUri,
        outputFile: tempUri.resolve('output.json'),
        outputDirectoryShared: tempUri2,
      )
      ..config.setupBuild(linkingEnabled: false)
      ..addExtension(
        CodeAssetExtension(
          targetOS: OS.current,
          macOS: OS.current == OS.macOS ? MacOSCodeConfig(targetVersion: defaultMacOSVersion) : null,
          targetArchitecture: Architecture.current,
          linkModePreference: LinkModePreference.dynamic,
          cCompiler: cCompiler,
        ),
      );

    final buildInput = BuildInput(buildInputBuilder.json);
    final buildOutput = BuildOutputBuilder();

    CMakeBuilder builder(Map<String, String?> defines) => CMakeBuilder.create(
      name: name,
      sourceDir: Directory(sourceDir).absolute.uri,
      buildMode: BuildMode.release,
      defines: defines,
      androidArgs: const AndroidBuilderArgs(),
      appleArgs: const AppleBuilderArgs(),
    );
    const skipMessage = 'CMake project is already successfully generated';

    await builder({}).run(input: buildInput, output: buildOutput, logger: logger);

    // Changed defines need a new generate.
    logMessages.clear();
    await builder({
      'FOO': 'BAR',
    }).run(input: buildInput, output: buildOutput, logger: logger, skipGenerateIfCached: true);
    expect(logMessages, isNot(contains(contains(skipMessage))));
    expect(logMessages, contains(contains('CMake generate command changed since the last generate')));

    // Unchanged defines skip it.
    logMessages.clear();
    await builder({
      'FOO': 'BAR',
    }).run(input: buildInput, output: buildOutput, logger: logger, skipGenerateIfCached: true);
    expect(logMessages, contains(contains(skipMessage)));
  });
}

/// Copies the files in [from] to [to], returns the absolute directory URI of [to].
Future<Uri> copyDirectory(Directory from, Directory to) async {
  final fromPath = from.absolute.uri.path;
  await for (final entity in from.list(recursive: true)) {
    if (entity is! File) continue;
    final target = File.fromUri(to.uri.resolve(entity.absolute.uri.path.substring(fromPath.length)));
    await target.parent.create(recursive: true);
    await entity.copy(target.path);
  }
  return to.absolute.uri;
}
