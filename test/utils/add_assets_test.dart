import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:native_toolchain_cmake/native_toolchain_cmake.dart';
import 'package:native_toolchain_cmake/src/utils/add_assets.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  final logger = Logger('AddAssetsTest');

  group('addLibraries', () {
    test('finds and adds library files matching expected names', () async {
      // Create temporary directories as URIs.
      final baseDir = await tempDirForTest();
      final sharedDir = await tempDirForTest();

      // Create a "lib" subdirectory.
      final libDir = Directory.fromUri(baseDir.resolve('lib'));
      await libDir.create();

      // Based on the current OS, create a dummy dynamic library file for the "add" project.
      final libFileName = OS.current.dylibFileName('add'); // e.g. add.dll, libadd.so, or add.dylib.
      final libFile = File.fromUri(baseDir.resolve('lib').resolve(libFileName));
      await libFile.writeAsString('dummy library content');

      final buildInputBuilder = BuildInputBuilder()
        ..setupShared(
          packageName: 'add',
          packageRoot: baseDir,
          outputFile: baseDir.resolve('output.json'),
          outputDirectoryShared: sharedDir,
        )
        ..config.setupBuild(linkingEnabled: true)
        ..addExtension(
          CodeAssetExtension(
            targetOS: OS.current,
            linkModePreference: LinkModePreference.dynamic,
            targetArchitecture: Architecture.current,
          ),
        );

      final buildInput = BuildInput(buildInputBuilder.json);

      {
        final buildOutput = BuildOutputBuilder();
        // Call addLibraries with the provided dynamic library names.
        final added = await buildOutput.findAndAddCodeAssets(
          buildInput,
          outDir: baseDir,
          names: {'add': 'add.dart'},
          logger: logger,
        );

        // Validate that one library file was added.
        expect(added.length, equals(1));
        // The file should reside in a "lib" subdirectory.
        expect(added.first.file?.toFilePath(), equals(libFile.absolute.path));
      }

      {
        final buildOutput = BuildOutputBuilder();
        // Call addLibraries with the provided dynamic library names.
        final added = await buildOutput.findAndAddCodeAssets(
          buildInput,
          outDir: baseDir,
          names: {r'(lib)?add\.(dll|so|dylib)': 'add.dart'},
          logger: logger,
          regExp: true,
        );

        // Validate that one library file was added.
        expect(added.length, equals(1));
        // The file should reside in a "lib" subdirectory.
        expect(added.first.file?.toFilePath(), equals(libFile.absolute.path));
      }
    });
  });

  test('does not add duplicate asset for the same library file', () async {
    // Create temporary directories as URIs.
    final baseDir = await tempDirForTest();
    final sharedDir = await tempDirForTest();

    // Create a "lib" subdirectory.
    final libDir = Directory.fromUri(baseDir.resolve('lib'));
    await libDir.create();

    // Based on the current OS, create a dummy dynamic library file for the "add" project.
    final libFileName = OS.current.dylibFileName('add'); // e.g. add.dll, libadd.so, or add.dylib.
    final libFile = File.fromUri(libDir.uri.resolve(libFileName));
    await libFile.writeAsString('dummy library content');

    final buildInputBuilder = BuildInputBuilder()
      ..setupShared(
        packageName: 'add',
        packageRoot: baseDir,
        outputFile: baseDir.resolve('output.json'),
        outputDirectoryShared: sharedDir,
      )
      ..config.setupBuild(linkingEnabled: true)
      ..addExtension(
        CodeAssetExtension(
          targetOS: OS.current,
          linkModePreference: LinkModePreference.dynamic,
          targetArchitecture: Architecture.current,
        ),
      );
    final buildInput = BuildInput(buildInputBuilder.json);
    final buildOutput = BuildOutputBuilder();

    // First call should add the asset.
    final addedFirst = await buildOutput.findAndAddCodeAssets(
      buildInput,
      outDir: baseDir,
      names: {'add': 'add.dart'},
      logger: logger,
    );
    expect(addedFirst.length, equals(1));

    // Second call should not add the asset again since it's already added.
    final addedSecond = await buildOutput.findAndAddCodeAssets(
      buildInput,
      outDir: baseDir,
      names: {'add': 'add.dart'},
      logger: logger,
    );
    // No assets should be added.
    expect(addedSecond.length, equals(0));
  });

  test('does not add duplicate asset when libraries exist in nested directories', () async {
    // Create temporary directories as URIs.
    final baseDir = await tempDirForTest();
    final sharedDir = await tempDirForTest();

    // Create a top-level "lib" subdirectory.
    final libDir = Directory.fromUri(baseDir.resolve('lib'));
    await libDir.create();

    // Create a nested subdirectory under "lib".
    final nestedDir = Directory.fromUri(libDir.uri.resolve('nested'));
    await nestedDir.create();

    // Determine the dynamic library file name.
    final libFileName = OS.current.dylibFileName('add');

    // Create a library file in the top-level "lib" directory.
    final topLibFile = File.fromUri(libDir.uri.resolve(libFileName));
    await topLibFile.writeAsString('top level library content');

    // Create another library file with the same name in the nested directory.
    final nestedLibFile = File.fromUri(nestedDir.uri.resolve(libFileName));
    await nestedLibFile.writeAsString('nested library content');

    final buildInputBuilder = BuildInputBuilder()
      ..setupShared(
        packageName: 'add',
        packageRoot: baseDir,
        outputFile: baseDir.resolve('output.json'),
        outputDirectoryShared: sharedDir,
      )
      ..config.setupBuild(linkingEnabled: true)
      ..addExtension(
        CodeAssetExtension(
          targetOS: OS.current,
          linkModePreference: LinkModePreference.dynamic,
          targetArchitecture: Architecture.current,
        ),
      );
    final buildInput = BuildInput(buildInputBuilder.json);
    final buildOutput = BuildOutputBuilder();

    // The call should find matching library files but add only one asset.
    final added = await buildOutput.findAndAddCodeAssets(
      buildInput,
      outDir: baseDir,
      names: {'add': 'add.dart'},
      logger: logger,
    );

    expect(added.length, equals(1));
  });

  group('link hook', () {
    Future<(BuildInput, File)> setup({required String libFileName}) async {
      final baseDir = await tempDirForTest();
      final sharedDir = await tempDirForTest();
      final libDir = Directory.fromUri(baseDir.resolve('lib'));
      await libDir.create();
      final libFile = File.fromUri(libDir.uri.resolve(libFileName));
      await libFile.writeAsString('dummy library content');

      final buildInputBuilder = BuildInputBuilder()
        ..setupShared(
          packageName: 'add',
          packageRoot: baseDir,
          outputFile: baseDir.resolve('output.json'),
          outputDirectoryShared: sharedDir,
        )
        ..config.setupBuild(linkingEnabled: true)
        ..addExtension(
          CodeAssetExtension(
            targetOS: OS.current,
            // The Dart and Flutter SDKs always prefer dynamic, also when linking.
            linkModePreference: LinkModePreference.dynamic,
            targetArchitecture: Architecture.current,
          ),
        );
      return (BuildInput(buildInputBuilder.json), libFile);
    }

    test('finds static libraries and routes them to the link hook', () async {
      final (buildInput, libFile) = await setup(libFileName: OS.current.staticlibFileName('add'));
      final buildOutputBuilder = BuildOutputBuilder();

      final added = await buildOutputBuilder.findAndAddCodeAssets(
        buildInput,
        outDir: libFile.parent.uri,
        names: {'add': 'add.dart'},
        linkModePreference: LinkModePreference.static,
        routing: const ToLinkHook('add'),
        logger: logger,
      );

      expect(added, hasLength(1));
      expect(added.single.linkMode, StaticLinking());
      expect(added.single.file?.toFilePath(), equals(libFile.absolute.path));
      final buildOutput = BuildOutput(buildOutputBuilder.json);
      expect(buildOutput.assets.encodedAssets, isEmpty);
      expect(buildOutput.assets.encodedAssetsForLinking['add'], hasLength(1));
    });

    test('does not find static libraries without linkModePreference', () async {
      final (buildInput, libFile) = await setup(libFileName: OS.current.staticlibFileName('add'));

      final added = await BuildOutputBuilder().findAndAddCodeAssets(
        buildInput,
        outDir: libFile.parent.uri,
        names: {'add': 'add.dart'},
        logger: logger,
      );

      expect(added, isEmpty);
    });

    test('deduplicates assets per routing', () async {
      final (buildInput, libFile) = await setup(libFileName: OS.current.dylibFileName('add'));
      final buildOutputBuilder = BuildOutputBuilder();
      final asset = CodeAsset(
        package: 'add',
        name: 'add.dart',
        linkMode: DynamicLoadingBundled(),
        file: libFile.uri,
      );

      expect(buildOutputBuilder.addCodeAsset(asset), isTrue);
      expect(buildOutputBuilder.addCodeAsset(asset), isFalse);
      expect(buildOutputBuilder.addCodeAsset(asset, routing: const ToLinkHook('add')), isTrue);
      expect(buildOutputBuilder.addCodeAsset(asset, routing: const ToLinkHook('add')), isFalse);
      expect(buildOutputBuilder.addedAssetIds, {asset.id});

      final buildOutput = BuildOutput(buildOutputBuilder.json);
      expect(buildOutput.assets.encodedAssets, hasLength(1));
      expect(buildOutput.assets.encodedAssetsForLinking['add'], hasLength(1));
    });
  });
}
