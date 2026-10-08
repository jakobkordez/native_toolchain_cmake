import 'dart:io';

import 'package:native_toolchain_cmake/src/builder/run_builder.dart';
import 'package:test/test.dart';

import '../helpers.dart';

void main() {
  test('RunCMakeBuilder resolves files inside outDir without a trailing slash', () async {
    final tempUri = await tempDirForTest();
    final outDir = Directory.fromUri(tempUri.resolve('out/'));
    await outDir.create();
    await File.fromUri(outDir.uri.resolve('ntc_last_generate_status.txt')).writeAsString('exitCode: 0\n');

    final runner = RunCMakeBuilder(sourceDir: tempUri, outDir: tempUri.resolve('out'));

    expect(runner.outDir, outDir.uri);
    expect(await runner.getLastGenExitCode(), 0);
  });
}
