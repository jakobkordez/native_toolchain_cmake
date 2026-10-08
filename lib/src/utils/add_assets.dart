// ignore_for_file: comment_references
import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

import '../builder/linkmode.dart';

extension BuildOutputBuilderCodeAssets on BuildOutputBuilder {
  /// Added asset ids, keyed by routing, see [_routingKey].
  static final Expando<Map<String, Set<String>>> _addedAssetIds = Expando<Map<String, Set<String>>>();

  /// Ids of the code assets added to the app bundle ([ToAppBundle]).
  Set<String> get addedAssetIds => _addedAssetIdsFor(const ToAppBundle());

  Set<String> _addedAssetIdsFor(AssetRouting routing) =>
      (_addedAssetIds[this] ??= {}).putIfAbsent(_routingKey(routing), () => <String>{});

  static String _routingKey(AssetRouting routing) =>
      routing is ToLinkHook ? 'ToLinkHook(${routing.packageName})' : '${routing.runtimeType}';

  /// Searches recursively through the provided [outDir] (or [input.outputDirectory]
  /// if not provided) for native library files that match the given [names]
  /// and adds them to [assets.code].
  ///
  /// [names] are used to map a found library file to package URI.
  /// e.g., for `foo_windows_x64.dll` -> `package:my_pkg/native_foo.dart`,
  /// should provide `{'foo_windows_x64': 'native_foo.dart'}`.
  ///
  /// If [regExp] is true, keys in [names] are treated as regular expression patterns to match library filenames.
  /// Use regExp if the built libraries are something like `libadd-1.dll`.
  /// e.g.,
  /// ```dart
  /// {r'(lib)?add-\d\.(dll|so|dylib)': 'native_foo.dart'}.
  /// ```
  ///
  /// The expected filename is computed using the current operating system's naming conventions
  /// combined with [linkMode], or a concrete [LinkMode] derived from
  /// [input.config.code.linkModePreference] if [linkMode] is null.
  /// For each file that ends with the computed library filename for one of the provided [names],
  /// a [CodeAsset] is created and added to [assets.code] with [routing] if it hasn't already been added.
  ///
  /// Duplicate assets are avoided by tracking previously added file paths internally
  /// as [assets] is not iterable.
  ///
  /// To hand static libraries to a link hook instead of bundling them, pass
  /// [StaticLinking] as [linkMode] and [ToLinkHook] as [routing]. This is only allowed
  /// if [input.config.linkingEnabled] is true, see [CMakeBuilder.staticWhenLinking].
  ///
  /// Returns a list of the added code assets.
  ///
  /// Example:
  /// ```dart
  /// final added = await output.findAndAddCodeAssets(
  ///   input,
  ///   output,
  ///   outDir: myOutputUri,
  ///   names: {'add': 'add.dart'},
  /// );
  /// ```
  ///
  /// ```dart
  /// final added = await output.findAndAddCodeAssets(
  ///   input,
  ///   output,
  ///   outDir: myOutputUri,
  ///   names: { r'(lib)?add\.(dll|so|dylib)': 'add.dart' },
  ///   regExp=true,
  /// );
  /// ```
  ///
  /// ```dart
  /// final linking = input.config.linkingEnabled;
  /// final added = await output.findAndAddCodeAssets(
  ///   input,
  ///   outDir: myOutputUri,
  ///   names: {'add': 'add.dart'},
  ///   linkMode: linking ? StaticLinking() : null,
  ///   routing: linking ? ToLinkHook(input.packageName) : const ToAppBundle(),
  /// );
  /// ```
  Future<List<CodeAsset>> findAndAddCodeAssets(
    BuildInput input, {
    required Map<String, String> names, // key: search library name, value: dart ffi name
    Uri? outDir,
    Logger? logger,
    bool regExp = false,
    LinkMode? linkMode,
    AssetRouting routing = const ToAppBundle(),
  }) async {
    final foundAssets = await findCodeAssets(
      input,
      names: names,
      outDir: outDir,
      logger: logger,
      regExp: regExp,
      linkMode: linkMode,
    );
    final addedAssets = addAllCodeAssets(foundAssets, logger: logger, routing: routing);
    return addedAssets;
  }

  /// Finds native library files in the provided [outDir] (or [input.outputDirectory] if not provided)
  ///
  /// [names] are used to map a found library file to package URI.
  /// e.g., for `foo_windows_x64.dll` -> `package:my_pkg/native_foo.dart`,
  /// should provide `{'foo_windows_x64': 'native_foo.dart'}`.
  ///
  /// If [regExp] is true, keys in [names] are treated as regular expression patterns to match library filenames.
  /// Use regExp if the built libraries are something like `libadd-1.dll`.
  /// e.g.,
  /// ```dart
  /// {r'(lib)?add-\d\.(dll|so|dylib)': 'native_foo.dart'}.
  /// ```
  ///
  /// The found assets get [linkMode], or a concrete [LinkMode] derived from
  /// [input.config.code.linkModePreference] if [linkMode] is null. Without [regExp],
  /// it also decides the expected file name, e.g. `libadd.a` instead of `libadd.so`.
  ///
  /// returns a list of the found code assets.
  Future<Set<CodeAsset>> findCodeAssets(
    BuildInput input, {
    required Map<String, String> names, // key: search library name, value: dart ffi name
    Uri? outDir,
    Logger? logger,
    bool regExp = false,
    LinkMode? linkMode,
  }) async {
    final preferredMode = input.config.code.linkModePreference;
    final searchDir = Directory.fromUri(outDir ?? input.outputDirectory);
    linkMode ??= getLinkMode(preferredMode);
    final Set<CodeAsset> foundAssets = {};

    logger?.info('Searching for libraries in ${searchDir.path}');
    logger?.info('Preferred link mode: $preferredMode, using link mode: $linkMode');

    await for (final entity in searchDir.list(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      for (final MapEntry(:key, value: assetName) in names.entries) {
        final found = regExp
            ? RegExp(key).hasMatch(p.basename(entity.path))
            : entity.path.endsWith(input.config.code.targetOS.libraryFileName(key, linkMode));
        if (!found) continue;
        logger?.info('Found library file: ${entity.path}');
        final asset = CodeAsset(
          package: input.packageName,
          name: assetName,
          linkMode: linkMode,
          file: entity.uri,
        );
        foundAssets.add(asset);
        break; // Only add one file per asset name.
      }
    }
    return foundAssets;
  }

  /// short for [assets.code.add]
  ///
  /// Returns false if an asset with the same id was already added with the same [routing].
  bool addCodeAsset(CodeAsset codeAsset, {AssetRouting routing = const ToAppBundle()}) {
    final addedIds = _addedAssetIdsFor(routing);
    // Only add if we haven't already added this file.
    if (addedIds.contains(codeAsset.id)) return false;
    assets.code.add(codeAsset, routing: routing);
    addedIds.add(codeAsset.id);
    return true;
  }

  /// add all code assets, won't add if already added
  List<CodeAsset> addAllCodeAssets(
    Iterable<CodeAsset> codeAssets, {
    Logger? logger,
    AssetRouting routing = const ToAppBundle(),
  }) {
    final addedAssets = <CodeAsset>[];
    for (final asset in codeAssets) {
      logger?.info('Adding asset: $asset');
      if (addCodeAsset(asset, routing: routing)) {
        addedAssets.add(asset);
      }
    }
    return addedAssets;
  }
}
